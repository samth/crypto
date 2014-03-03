;; Copyright 2014 Ryan Culpepper
;; 
;; This library is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; 
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Lesser General Public License for more details.
;; 
;; You should have received a copy of the GNU Lesser General Public License
;; along with this library.  If not, see <http://www.gnu.org/licenses/>.

#lang racket/base
(require ffi/unsafe
         racket/class
         racket/match
         "../common/interfaces.rkt"
         "../common/common.rkt"
         "../common/catalog.rkt"
         "../common/error.rkt"
         "../gmp/ffi.rkt"
         "ffi.rkt")
(provide (all-defined-out))

;; ============================================================

(define nettle-read-key%
  (class* impl-base% (pk-read-key<%>)
    (inherit-field factory)
    (super-new (spec 'nettle-read-key))

    (define/public (read-key sk)
      (define (bad) #f)
      (match sk
        ;; RSA, DSA private keys
        [(list 'rsa 'private 'pkcs1 (? bytes? buf))
         (bad)]
        [(list 'dsa 'private 'libcrypto (? bytes? buf))
         (bad)]
        [(list (or 'rsa 'dsa) 'private 'pkcs8 (? bytes? buf)) ;; PrivateKeyInfo
         (bad)]
        ;; RSA, DSA public keys (and maybe others too?)
        [(list (or 'rsa 'dsa 'ec) 'public 'pkix (? bytes? buf)) ;; SubjectPublicKeyInfo
         (bad)]
        [(list 'ec 'private 'sec1 (? bytes? buf)) ;; ECPrivateKey
         (bad)]
        ;; Ad hoc
        [(list 'rsa 'private 'nettle
               (? bytes? n) (? bytes? e)
               (? bytes? d) (? bytes? p) (? bytes? q)
               (? bytes? a) (? bytes? b) (? bytes? c))
         (define pub (new-rsa_public_key))
         (define priv (new-rsa_private_key))
         (__gmpz_set (rsa_public_key_struct-n pub) (bin->mpz n))
         (__gmpz_set (rsa_public_key_struct-e pub) (bin->mpz e))
         (__gmpz_set (rsa_private_key_struct-d priv) (bin->mpz d))
         (__gmpz_set (rsa_private_key_struct-p priv) (bin->mpz p))
         (__gmpz_set (rsa_private_key_struct-q priv) (bin->mpz q))
         (__gmpz_set (rsa_private_key_struct-a priv) (bin->mpz a))
         (__gmpz_set (rsa_private_key_struct-b priv) (bin->mpz b))
         (__gmpz_set (rsa_private_key_struct-c priv) (bin->mpz c))
         (define impl (send factory get-pk 'rsa))
         (new nettle-rsa-key% (impl impl) (pub pub) (priv priv))]
        [(list 'rsa 'public 'nettle
               (? bytes? n) (? bytes? e))
         (define pub (new-rsa_public_key))
         (__gmpz_set (rsa_public_key_struct-n pub) (bin->mpz n))
         (__gmpz_set (rsa_public_key_struct-e pub) (bin->mpz e))
         (define impl (send factory get-pk 'rsa))
         (new nettle-rsa-key% (impl impl) (pub pub) (priv #f))]
        [_ #f]))

    (define/public (read-params sp) #f)
    ))

;; ============================================================

(define nettle-pk-impl%
  (class* impl-base% (pk-impl<%>)
    (inherit-field spec factory)
    (super-new)

    (define/public (generate-key config)
      (err/no-direct-keygen spec))
    (define/public (generate-params config)
      (err/no-params spec))
    (define/public (can-encrypt?) #f)
    (define/public (can-sign?) #f)
    (define/public (can-key-agree?) #f)
    (define/public (has-params?) #f)

    (define/public (get-random-ctx)
      (define r (send factory get-random))
      (send r get-context))
    ))

;; ============================================================

(define allowed-rsa-keygen
  `((nbits ,exact-positive-integer? "exact-positive-integer?")
    (e     ,exact-positive-integer? "exact-positive-integer?")))

(define nettle-rsa-impl%
  (class nettle-pk-impl%
    (inherit-field spec factory)
    (inherit get-random-ctx)
    (super-new (spec 'rsa))

    (define/override (can-encrypt?) #t)
    (define/override (can-sign?) #t)

    (define/override (generate-key config)
      (check-keygen-spec config allowed-rsa-keygen)
      (let ([nbits (or (keygen-spec-ref config 'nbits) 2048)]
            [e (or (keygen-spec-ref config 'e) 65537)])
        (define pub (new-rsa_public_key))
        (define priv (new-rsa_private_key))
        (__gmpz_set_si (rsa_public_key_struct-e pub) e)
        (or (nettle_rsa_generate_keypair pub priv (get-random-ctx) nbits 0)
            (crypto-error "RSA key generation failed"))
        (new nettle-rsa-key% (impl this) (pub pub) (priv priv))))
    ))

(define nettle-rsa-key%
  (class* ctx-base% (pk-key<%>)
    (init-field pub priv)
    (inherit-field impl)
    (super-new)

    (define/public (is-private?) (and priv #t))

    (define/public (get-public-key)
      (if priv (new nettle-rsa-key% (impl impl) (pub pub) (priv #f)) this))

    (define/public (get-params)
      (crypto-error "key parameters not supported"))

    (define/public (write-key fmt)
      (case fmt
        [(#f)
         (cond [priv
                `(rsa private nettle
                      ,(mpz->bin (rsa_public_key_struct-n pub))
                      ,(mpz->bin (rsa_public_key_struct-e pub))
                      ,(mpz->bin (rsa_private_key_struct-d priv))
                      ,(mpz->bin (rsa_private_key_struct-p priv))
                      ,(mpz->bin (rsa_private_key_struct-q priv))
                      ,(mpz->bin (rsa_private_key_struct-a priv))
                      ,(mpz->bin (rsa_private_key_struct-b priv))
                      ,(mpz->bin (rsa_private_key_struct-c priv)))]
               [else
                `(rsa public nettle
                      ,(mpz->bin (rsa_public_key_struct-n pub))
                      ,(mpz->bin (rsa_public_key_struct-e pub)))])]
        [else
         (err/key-format fmt)]))

    (define/public (equal-to-key? other)
      (and (is-a? other nettle-rsa-key%)
           (= (rsa_public_key_struct-size pub)
              (rsa_public_key_struct-size (get-field pub other)))
           (mpz=? (rsa_public_key_struct-n pub)
                  (rsa_public_key_struct-n (get-field pub other)))
           (mpz=? (rsa_public_key_struct-e pub)
                  (rsa_public_key_struct-e (get-field pub other)))))

    (define/public (sign digest digest-spec pad)
      (unless (send impl can-sign?) (err/no-sign (send impl get-spec)))
      (unless priv (err/sign-requires-private))
      (check-digest digest digest-spec)
      (define sign-fun
        (case digest-spec
          [(md5) nettle_rsa_md5_sign_digest]
          [(sha1) nettle_rsa_sha1_sign_digest]
          [(sha256) nettle_rsa_sha256_sign_digest]
          [(sha512) nettle_rsa_sha512_sign_digest]
          [else
           (crypto-error "RSA signing not supported for digest\n  digest algorithm: ~s"
                         digest-spec)]))
      (define sigz (new-mpz))
      (or (sign-fun priv digest sigz)
          (crypto-error "RSA signing failed"))
      (mpz->bin sigz))

    (define/private (check-digest digest digest-spec)
      (unless (= (bytes-length digest)
                 (digest-spec-size digest-spec))
        (crypto-error
         "digest wrong size\n  digest algorithm: ~s\n  expected size:  ~s\n  digest: ~e"
         digest-spec (digest-spec-size digest-spec) digest)))

    (define/public (verify digest digest-spec pad sig)
      (unless (send impl can-sign?) (err/no-sign (send impl get-spec)))
      (check-digest digest digest-spec)
      (define verify-fun
        (case digest-spec
          [(md5) nettle_rsa_md5_verify_digest]
          [(sha1) nettle_rsa_sha1_verify_digest]
          [(sha256) nettle_rsa_sha256_verify_digest]
          [(sha512) nettle_rsa_sha512_verify_digest]
          [else
           (crypto-error "RSA verification not supported for digest\n  digest algorithm: ~s\n"
                         digest-spec)]))
      (unless (member pad '(#f pkcs1-v1.5))
        (crypto-error "RSA padding not supported\n  padding: ~s" pad))
      (define sigz (bin->mpz sig))
      (verify-fun pub digest sigz))

    (define/public (encrypt buf pad)
      (unless (send impl can-encrypt?) (err/no-encrypt (send impl get-spec)))
      (unless (member pad '(#f pkcs1-v1.5))
        (crypto-error "bad pad")) ;; FIXME
      (define enc-z (new-mpz))
      (or (nettle_rsa_encrypt pub (send impl get-random-ctx) buf enc-z)
          (crypto-error "RSA encyption failed"))
      (mpz->bin enc-z))

    (define/public (decrypt buf pad)
      (unless (send impl can-encrypt?) (err/no-encrypt (send impl get-spec)))
      (unless priv (err/decrypt-requires-private))
      (define enc-z (bin->mpz buf))
      (define dec-buf (make-bytes (rsa_public_key_struct-size pub)))
      (define dec-size (nettle_rsa_decrypt priv dec-buf enc-z))
      (unless dec-size
        (crypto-error "RSA decryption failed"))
      (shrink-bytes dec-buf dec-size))

    (define/public (compute-secret peer-pubkey0)
      (crypto-error "not supported"))
    ))