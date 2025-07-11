(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-verified (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-retirement (err u105))

;; Define data variables
(define-data-var total-credits uint u0)
(define-data-var verification-threshold uint u1000)
(define-data-var credit-price uint u100)
(define-data-var total-retired uint u0)
(define-data-var retirement-certificate-counter uint u0)

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
(define-map retirement-certificates
    uint
    {
        retirer: principal,
        amount: uint,
        timestamp: uint,
        purpose: (string-ascii 100),
        organization: (optional (string-ascii 50)),
    }
)
(define-map user-retirement-totals
    principal
    uint
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

;; Retirement Functions
(define-public (retire-credits
        (amount uint)
        (purpose (string-ascii 100))
        (organization (optional (string-ascii 50)))
    )
    (let (
            (current-balance (ft-get-balance carbon-credits tx-sender))
            (certificate-id (+ (var-get retirement-certificate-counter) u1))
            (current-user-total (default-to u0 (map-get? user-retirement-totals tx-sender)))
        )
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= current-balance amount) err-insufficient-balance)
            (try! (ft-burn? carbon-credits amount tx-sender))
            (map-set retirement-certificates certificate-id {
                retirer: tx-sender,
                amount: amount,
                timestamp: burn-block-height,
                purpose: purpose,
                organization: organization,
            })
            (map-set user-retirement-totals tx-sender
                (+ current-user-total amount)
            )
            (var-set total-retired (+ (var-get total-retired) amount))
            (var-set retirement-certificate-counter certificate-id)
            (ok certificate-id)
        )
    )
)

(define-public (retire-credits-for-organization
        (amount uint)
        (purpose (string-ascii 100))
        (organization (string-ascii 50))
        (beneficiary principal)
    )
    (let (
            (current-balance (ft-get-balance carbon-credits tx-sender))
            (certificate-id (+ (var-get retirement-certificate-counter) u1))
            (current-user-total (default-to u0 (map-get? user-retirement-totals beneficiary)))
        )
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= current-balance amount) err-insufficient-balance)
            (try! (ft-burn? carbon-credits amount tx-sender))
            (map-set retirement-certificates certificate-id {
                retirer: beneficiary,
                amount: amount,
                timestamp: burn-block-height,
                purpose: purpose,
                organization: (some organization),
            })
            (map-set user-retirement-totals beneficiary
                (+ current-user-total amount)
            )
            (var-set total-retired (+ (var-get total-retired) amount))
            (var-set retirement-certificate-counter certificate-id)
            (ok certificate-id)
        )
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

;; Retirement Read-Only Functions
(define-read-only (get-retirement-certificate (certificate-id uint))
    (map-get? retirement-certificates certificate-id)
)

(define-read-only (get-user-retirement-total (user principal))
    (default-to u0 (map-get? user-retirement-totals user))
)

(define-read-only (get-total-retired)
    (var-get total-retired)
)

(define-read-only (get-retirement-certificate-count)
    (var-get retirement-certificate-counter)
)

(define-read-only (get-retirement-stats)
    (let ((total-supply (ft-get-supply carbon-credits)))
        (ok {
            total-retired: (var-get total-retired),
            total-certificates: (var-get retirement-certificate-counter),
            retirement-percentage: (if (> total-supply u0)
                (/ (* (var-get total-retired) u10000) total-supply)
                u0
            ),
        })
    )
)
