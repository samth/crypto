;; Copyright 2013 Ryan Culpepper
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
(require racket/class
         racket/match
         racket/syntax
         ffi/unsafe
         "../common/interfaces.rkt"
         "../common/common.rkt"
         "ffi.rkt"
         "digest.rkt"
         "cipher.rkt")
(provide nettle-factory)

;; ----------------------------------------

(define digests
  `(;;[Name     String]
    [md2       "md2"]
    [md4       "md4"]
    [md5       "md5"]
    [ripemd160 "ripemd160"]
    [sha1      "sha1"]
    [sha224    "sha224"]
    [sha256    "sha256"]
    [sha384    "sha384"]
    [sha512    "sha512"]))

;; ----------------------------------------

;; FIXME: Probably ok to skip multikeylen indirection, since
;; "aes128" cipher can probably actually support all legal keylens,
;; it just *advertises* 128-bit keys.

(define ciphers
  `(;;[Name   String/([KeySize String] ...)]
    [aes ([128 "aes128"]
          [192 "aes192"]
          [256 "aes256"])]
    [blowfish "blowfish"]
    [camellia ([128 "camellia128"]
               [192 "camellia192"]
               [256 "camellia256"])]
    [cast-128 ([128 "cast128"])]
    [salsa20 "salsa20"]
    [salsa20r12 "salsa20r12"]
    [serpent ([128 "serpent128"]
              [192 "serpent192"]
              [256 "serpent256"])]
    [twofish ([128 "twofish128"]
              [192 "twofish192"]
              [256 "twofish256"])]
    [rc4 "arcfour128"]
    ;; "arctwo40", "arctwo64", "arctwo128"
    ))

(define modes '(ecb cbc ctr stream)) ;; FIXME: support GCM

;; ----------------------------------------

(define nettle-factory%
  (class* object% (#|factory<%>|#)
    (super-new)

    (define digest-table (make-hasheq))
    (define cipher-table (make-hash))

    (define/private (intern-digest spec)
      (cond [(hash-ref digest-table spec #f)
             => values]
            [(assq spec digests)
             => (lambda (entry)
                  (let ([algid (cadr entry)])
                    (cond [(assoc algid nettle-hashes)
                           => (lambda (entry)
                                (let* ([nh (cadr entry)]
                                       [di (new digest-impl%
                                                (spec spec)
                                                (nh nh))])
                                  (hash-set! digest-table spec di)))]
                          [else #f])))]
            [else #f]))

    (define/private (intern-cipher spec)
      (cond [(hash-ref cipher-table spec #f)
             => values]
            [else
             (let ([ci (get-cipher spec)])
               (when ci (hash-set! cipher-table spec ci))
               ci)]))

    (define/private (get-cipher spec)
      (and (memq (cadr spec) modes)
           (let ([entry (assq (car spec) ciphers)])
             (match entry
               [(list _ (? string? algid))
                (get-nc spec algid)]
               [(list _ keylens+algids)
                (let* ([impls
                        (for/list ([keylen+algid (in-list keylens+algids)])
                          (cons (quotient (car keylen+algid) 8)
                                (get-nc spec (cadr keylen+algid))))]
                       [impls (filter cdr impls)])
                  (and (pair? impls)
                       (new multikeylen-cipher-impl%
                            (spec spec)
                            (impls impls))))]))))

    (define/private (get-nc spec algid)
      (match (assoc algid nettle-more-ciphers)
        [(list* _ nc extras)
         (new cipher-impl% (spec spec) (nc nc) (extras extras))]
        [_ #f]))

    ;; ----

    (define/public (get-digest-by-name name)
      (intern-digest name))
    (define/public (get-cipher-by-name name)
      (intern-cipher name))
    (define/public (get-random)
      #f)
    ))

(define nettle-factory (new nettle-factory%))