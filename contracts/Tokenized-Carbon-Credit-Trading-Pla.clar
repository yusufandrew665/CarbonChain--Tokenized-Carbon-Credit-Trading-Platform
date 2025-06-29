(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-verified (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-unauthorized (err u103))

;; Define data variables
(define-data-var total-credits uint u0)
(define-data-var verification-threshold uint u1000)
(define-data-var credit-price uint u100)

;; Define data maps
(define-map credit-balances
    principal
    uint
)
(define-map verifier-status
    principal
    bool
)
(define-map credit-metadata
    uint
    {
        owner: principal,
        amount: uint,
        verified: bool,
        timestamp: uint,
    }
)
(define-map pending-verifications
    uint
    bool
)

(define-fungible-token carbon-credits)

;; Core Functions
(define-public (mint-credits (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (let ((new-id (+ (var-get total-credits) u1)))
            (try! (ft-mint? carbon-credits amount tx-sender))
            (map-set credit-metadata new-id {
                owner: tx-sender,
                amount: amount,
                verified: false,
                timestamp: burn-block-height,
            })
            (var-set total-credits new-id)
            (ok new-id)
        )
    )
)

(define-public (verify-credits (credit-id uint))
    (let ((credit (unwrap! (map-get? credit-metadata credit-id) err-not-verified)))
        (asserts! (is-verifier tx-sender) err-unauthorized)
        (asserts! (not (get verified credit)) err-not-verified)
        (map-set credit-metadata credit-id (merge credit { verified: true }))
        (ok true)
    )
)

(define-public (transfer-credits
        (amount uint)
        (recipient principal)
    )
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-transfer? carbon-credits amount tx-sender recipient))
        (ok true)
    )
)

(define-public (burn-credits (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (ft-burn? carbon-credits amount tx-sender))
        (ok true)
    )
)

;; Marketplace Functions
(define-public (list-credits-for-sale
        (amount uint)
        (price uint)
    )
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (> price u0) err-invalid-amount)
        (try! (ft-transfer? carbon-credits amount tx-sender (as-contract tx-sender)))
        (ok true)
    )
)

(define-public (buy-credits
        (amount uint)
        (seller principal)
    )
    (let ((total-cost (* amount (var-get credit-price))))
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (try! (stx-transfer? total-cost tx-sender seller))
            (try! (ft-transfer? carbon-credits amount (as-contract tx-sender) tx-sender))
            (ok true)
        )
    )
)

;; Admin Functions
(define-public (set-verifier
        (address principal)
        (status bool)
    )
    (begin
        (asserts! (is-contract-owner tx-sender) err-owner-only)
        (map-set verifier-status address status)
        (ok true)
    )
)

(define-public (update-credit-price (new-price uint))
    (begin
        (asserts! (is-contract-owner tx-sender) err-owner-only)
        (var-set credit-price new-price)
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-credit-balance (owner principal))
    (default-to u0 (map-get? credit-balances owner))
)

(define-read-only (get-credit-info (credit-id uint))
    (map-get? credit-metadata credit-id)
)

(define-read-only (is-verifier (address principal))
    (default-to false (map-get? verifier-status address))
)

(define-read-only (is-contract-owner (address principal))
    (is-eq address contract-owner)
)

(define-read-only (get-total-supply)
    (ft-get-supply carbon-credits)
)

;; SIP-010 Required Functions
(define-read-only (get-name)
    (ok "Carbon Credits")
)

(define-read-only (get-symbol)
    (ok "CARB")
)

(define-read-only (get-decimals)
    (ok u6)
)

(define-read-only (get-balance (account principal))
    (ok (ft-get-balance carbon-credits account))
)

(define-read-only (get-total-credits)
    (ok (var-get total-credits))
)

(define-public (set-verification-threshold (new-threshold uint))
    (begin
        (asserts! (is-contract-owner tx-sender) err-owner-only)
        (var-set verification-threshold new-threshold)
        (ok true)
    )
)
