;; mzcrypto: libcrypto bindings for PLT-scheme
;; Diffie-Hellman key exchange
;; 
;; (C) Copyright 2007-2009 Dimitris Vyzovitis <vyzo at media.mit.edu>
;; 
;; mzcrypto is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published
;; by the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;; 
;; mzcrypto is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU Lesser General Public License for more details.
;; 
;; You should have received a copy of the GNU Lesser General Public License
;; along with mzcrypto.  If not, see <http://www.gnu.org/licenses/>.
#lang racket/base
(require ffi/unsafe
         ffi/unsafe/alloc
         "libcrypto.rkt"
         "macros.rkt"
         "error.rkt"
         "bn.rkt"
         (only-in net/base64 base64-decode)
         (only-in racket/list last)
         (for-syntax racket/base
                     racket/syntax
                     "stx-util.rkt"))

(define-struct !dh (bits bs))
(define-struct dhkey (p))

(define-cpointer-type _DH)

(define-crypto DH_free
  (_fun _DH -> _void)
  #:wrap (deallocator))

(define-crypto DH_new
  (_fun -> _DH/null)
  #:wrap (allocator DH_free))

(define-crypto DH_size
  (_fun _DH -> _int))

(define-crypto DH_generate_key
  (_fun _DH -> _int)
  #:wrap (err-wrap/check 'DH_generate_key))

(define-crypto DH_compute_key
  (_fun _pointer
        _BIGNUM
        _DH
        -> _int)
  #:wrap (err-wrap/check 'DH_compute_key))

(define-crypto d2i_DHparams
  (_fun (_pointer = #f)
        (_ptr i _pointer)
        _long
        -> (result : _DH/null))
  #:wrap (compose (allocator DH_free) (err-wrap/pointer 'd2i_DHparams)))

;; DH: struct dh_st {pad version p g length pub_key ...}
(define (dhkey-pubk dh)
  (bn->bytes
   (last 
    (ptr-ref (dhkey-p dh) 
      (_list-struct _int _int _BIGNUM _BIGNUM _long _BIGNUM)))))

(define (params->dhkey params)
  (let* ([bs (!dh-bs params)]
         [dhp (d2i_DHparams bs (bytes-length bs))])
    (make-dhkey dhp)))

(define (dhkey-size dh)
  (DH_size (dhkey-p dh)))

(define (generate-dhkey params)
  (let ([dh (params->dhkey params)])
    (DH_generate_key (dhkey-p dh))
    (values dh (dhkey-pubk dh))))

(define (compute-key dh pubk)
  (let* ([bs (make-bytes (dhkey-size dh))]
         [bn (bytes->bn pubk)])
    (DH_compute_key bs bn (dhkey-p dh))
    (BN_free bn)
    bs))

(define-syntax (define-dh stx)
  (syntax-case stx ()
    [(_ bits bbs)
     (with-syntax ([params (format-id stx "dh:~a" (syntax-e #'bits))])
       #'(begin
           (define params (make-!dh bits (base64-decode bbs)))
           (put-symbols! dh.symbols params)))]))

(define-symbols dh.symbols
  !dh? dhkey? (!dh-bits dh-bits) dhkey-size compute-key)

;; DH parameter generation can take a really long time
;; These are base64 encoded defaults provided by the OpenSSL project.
;; openssl dhparam can be used to generate new ones
(define-dh 192
  #"MB4CGQDUoLoCULb9LsYm5+/WN992xxbiLQlEuIsCAQM=")
(define-dh 512
  #"MEYCQQDaWDwW2YUiidDkr3VvTMqS3UvlM7gE+w/tlO+cikQD7VdGUNNpmdsp13Yn
    a6LT1BLiGPTdHghM9tgAPnxHdOgzAgEC")
(define-dh 1024
  #"MIGHAoGBAJf2QmHKtQXdKCjhPx1ottPb0PMTBH9A6FbaWMsTuKG/K3g6TG1Z1fkq
    /Gz/PWk/eLI9TzFgqVAuPvr3q14a1aZeVUMTgo2oO5/y2UHe6VaJ+trqCTat3xlx
    /mNbIK9HA2RgPC3gWfVLZQrY+gz3ASHHR5nXWHEyvpuZm7m3h+irAgEC")
(define-dh 2048
  #"MIIBCAKCAQEA7ZKJNYJFVcs7+6J2WmkEYb8h86tT0s0h2v94GRFS8Q7B4lW9aG9o
    AFO5Imov5Jo0H2XMWTKKvbHbSe3fpxJmw/0hBHAY8H/W91hRGXKCeyKpNBgdL8sh
    z22SrkO2qCnHJ6PLAMXy5fsKpFmFor2tRfCzrfnggTXu2YOzzK7q62bmqVdmufEo
    pT8igNcLpvZxk5uBDvhakObMym9mX3rAEBoe8PwttggMYiiw7NuJKO4MqD1llGkW
    aVM8U2ATsCun1IKHrRxynkE1/MJ86VHeYYX8GZt2YA8z+GuzylIOKcMH6JAWzMwA
    Gbatw6QwizOhr9iMjZ0B26TE3X8LvW84wwIBAg==")
(define-dh 4096
  #"MIICCAKCAgEA/urRnb6vkPYc/KEGXWnbCIOaKitq7ySIq9dTH7s+Ri59zs77zty7
    vfVlSe6VFTBWgYjD2XKUFmtqq6CqXMhVX5ElUDoYDpAyTH85xqNFLzFC7nKrff/H
    TFKNttp22cZE9V0IPpzedPfnQkE7aUdmF9JnDyv21Z/818O93u1B4r0szdnmEvEF
    bKuIxEHX+bp0ZR7RqE1AeifXGJX3d6tsd2PMAObxwwsv55RGkn50vHO4QxtTARr1
    rRUV5j3B3oPMgC7Offxx+98Xn45B1/G0Prp11anDsR1PGwtaCYipqsvMwQUSJtyE
    EOQWk+yFkeMe4vWv367eEi0Sd/wnC+TSXBE3pYvpYerJ8n1MceI5GQTdarJ77OW9
    bGTHmxRsLSCM1jpLdPja5jjb4siAa6EHc4qN9c/iFKS3PQPJEnX7pXKBRs5f7AF3
    W3RIGt+G9IVNZfXaS7Z/iCpgzgvKCs0VeqN38QsJGtC1aIkwOeyjPNy2G6jJ4yqH
    ovXYt/0mc00vCWeSNS1wren0pR2EiLxX0ypjjgsU1mk/Z3b/+zVf7fZSIB+nDLjb
    NPtUlJCVGnAeBK1J1nG3TQicqowOXoM6ISkdaXj5GPJdXHab2+S7cqhKGv5qC7rR
    jT6sx7RUr0CNTxzLI7muV2/a4tGmj0PSdXQdsZ7tw7gbXlaWT1+MM2MCAQI=")

(define-provider provide-dh dh.symbols)

(provide-dh)
(provide provide-dh generate-dhkey
         (struct-out !dh)
         (struct-out dhkey))