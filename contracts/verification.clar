;; TrustChain: Decentralized Identity Verification Network
;; This contract implements a decentralized identity verification system where:
;; 1. Trusted validators can certify user identities
;; 2. Users can submit their information for certification
;; 3. Third parties can check if a user is certified
;; 4. Users maintain control over their identity data

(define-constant admin-address tx-sender)

;; Error codes
(define-constant error-unauthorized (err u100))
(define-constant error-already-validator (err u101))
(define-constant error-not-validator (err u102))
(define-constant error-identity-already-certified (err u103))
(define-constant error-identity-not-certified (err u104))
(define-constant error-invalid-trust-tier (err u105))
(define-constant error-not-admin (err u106))
(define-constant error-invalid-identity-proof (err u107))

;; Data structures
(define-map validators principal bool)
(define-map identity-certification 
  { account: principal } 
  { 
    certified: bool, 
    trust-tier: uint, 
    certification-timestamp: uint, 
    identity-proof: (buff 32),
    validator: principal 
  }
)

;; Trust tiers
;; 1 = Standard tier
;; 2 = Enhanced tier
;; 3 = Premium tier

;; Read-only functions

;; Check if an address is an authorized validator
(define-read-only (is-validator (address principal))
  (default-to false (get-validator-status address))
)

;; Get validator status
(define-read-only (get-validator-status (address principal))
  (map-get? validators address)
)

;; Check if a user's identity is certified
(define-read-only (is-identity-certified (account principal))
  (default-to false (get certified (get-identity-certification account)))
)

;; Get identity certification details
(define-read-only (get-identity-certification (account principal))
  (map-get? identity-certification { account: account })
)

;; Get identity trust tier
(define-read-only (get-identity-trust-tier (account principal))
  (default-to u0 (get trust-tier (get-identity-certification account)))
)

;; Helper function to validate trust tier
(define-private (is-valid-trust-tier (tier uint))
  (or (is-eq tier u1) (is-eq tier u2) (is-eq tier u3))
)

;; Helper function to validate identity proof (non-zero)
(define-private (is-valid-identity-proof (proof (buff 32)))
  (not (is-eq proof 0x0000000000000000000000000000000000000000000000000000000000000000))
)

;; Public functions

;; Add a new validator (only admin can do this)
(define-public (register-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender admin-address) error-unauthorized)
    (asserts! (not (is-validator validator)) error-already-validator)
    (ok (map-set validators validator true))
  )
)

;; Remove a validator (only admin can do this)
(define-public (unregister-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender admin-address) error-unauthorized)
    (asserts! (is-validator validator) error-not-validator)
    (ok (map-set validators validator false))
  )
)

;; Certify an identity (only authorized validators can do this)
(define-public (certify-identity (account principal) (trust-tier uint) (identity-proof (buff 32)))
  (begin
    (asserts! (is-validator tx-sender) error-unauthorized)
    (asserts! (is-valid-trust-tier trust-tier) error-invalid-trust-tier)
    (asserts! (is-valid-identity-proof identity-proof) error-invalid-identity-proof)
    
    ;; Use a variable to store the sanitized identity data structure
    (let ((account-entry { account: account })
          (certification-data { 
            certified: true, 
            trust-tier: trust-tier, 
            certification-timestamp: block-height, 
            identity-proof: identity-proof,
            validator: tx-sender 
          }))
      (ok (map-set identity-certification account-entry certification-data))
    )
  )
)

;; Revoke certification for an identity (can be done by the validator who certified the identity or admin)
(define-public (revoke-certification (account principal))
  (let ((current-certification (unwrap! (get-identity-certification account) error-identity-not-certified))
        (account-entry { account: account })
        (revoked-data { 
          certified: false, 
          trust-tier: u0, 
          certification-timestamp: block-height, 
          identity-proof: 0x0000000000000000000000000000000000000000000000000000000000000000,
          validator: tx-sender 
        }))
    (begin
      (asserts! (or 
                 (is-eq tx-sender (get validator current-certification))
                 (is-eq tx-sender admin-address)) 
                error-unauthorized)
      (ok (map-set identity-certification account-entry revoked-data))
    )
  )
)

;; Users can remove their own certification (self-revocation)
(define-public (self-revoke-certification)
  (let ((account tx-sender)
        (account-entry { account: tx-sender })
        (revoked-data { 
          certified: false, 
          trust-tier: u0, 
          certification-timestamp: block-height, 
          identity-proof: 0x0000000000000000000000000000000000000000000000000000000000000000,
          validator: tx-sender 
        }))
    (begin
      (asserts! (is-identity-certified account) error-identity-not-certified)
      (ok (map-set identity-certification account-entry revoked-data))
    )
  )
)

;; Update trust tier (only authorized validators can do this)
(define-public (update-trust-tier (account principal) (new-trust-tier uint))
  (let ((current-certification (unwrap! (get-identity-certification account) error-identity-not-certified))
        (account-entry { account: account }))
    (begin
      (asserts! (is-validator tx-sender) error-unauthorized)
      (asserts! (is-valid-trust-tier new-trust-tier) error-invalid-trust-tier)
      
      ;; Create an updated certification record with the new tier
      (let ((updated-certification (merge current-certification { trust-tier: new-trust-tier })))
        (ok (map-set identity-certification account-entry updated-certification))
      )
    )
  )
)