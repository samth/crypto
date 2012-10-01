;; mzcrypto: libcrypto bindings for PLT-scheme
;; BN interface
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
(require "ffi.rkt"
         "util.rkt")
(provide (all-defined-out))

(define (bn-size bn)
  (ceiling (/ (BN_num_bits bn) 8)))

(define (bn->bytes bn)
  (let ([bs (make-bytes (bn-size bn))])
    (shrink-bytes bs (BN_bn2bin bn bs))))

(define (bytes->bn bs)
  (BN_bin2bn bs))