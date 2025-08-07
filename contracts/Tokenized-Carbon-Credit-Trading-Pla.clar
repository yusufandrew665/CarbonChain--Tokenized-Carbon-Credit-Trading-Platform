(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-verified (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-retirement (err u105))
(define-constant err-insufficient-staked (err u106))
(define-constant err-stake-locked (err u107))
(define-constant err-no-stake (err u108))

;; Define data variables
(define-data-var total-credits uint u0)
(define-data-var verification-threshold uint u1000)
(define-data-var credit-price uint u100)
(define-data-var total-retired uint u0)
(define-data-var retirement-certificate-counter uint u0)
(define-data-var total-staked uint u0)
(define-data-var stake-reward-rate uint u5)

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
(define-map user-stakes
    principal
    {
        amount: uint,
        start-block: uint,
        lock-period: uint,
    }
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

;; Staking Functions
(define-public (stake-credits
        (amount uint)
        (lock-blocks uint)
    )
    (let (
            (current-balance (ft-get-balance carbon-credits tx-sender))
            (existing-stake (map-get? user-stakes tx-sender))
        )
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (>= current-balance amount) err-insufficient-balance)
            (asserts! (is-none existing-stake) err-stake-locked)
            (try! (ft-transfer? carbon-credits amount tx-sender (as-contract tx-sender)))
            (map-set user-stakes tx-sender {
                amount: amount,
                start-block: burn-block-height,
                lock-period: lock-blocks,
            })
            (var-set total-staked (+ (var-get total-staked) amount))
            (ok true)
        )
    )
)

(define-public (unstake-credits)
    (let (
            (stake-info (unwrap! (map-get? user-stakes tx-sender) err-no-stake))
            (stake-amount (get amount stake-info))
            (start-block (get start-block stake-info))
            (lock-period (get lock-period stake-info))
            (blocks-staked (- burn-block-height start-block))
            (reward-amount (calculate-stake-reward stake-amount blocks-staked))
        )
        (begin
            (asserts! (>= blocks-staked lock-period) err-stake-locked)
            (try! (ft-transfer? carbon-credits stake-amount (as-contract tx-sender)
                tx-sender
            ))
            (try! (ft-mint? carbon-credits reward-amount tx-sender))
            (map-delete user-stakes tx-sender)
            (var-set total-staked (- (var-get total-staked) stake-amount))
            (ok reward-amount)
        )
    )
)

(define-private (calculate-stake-reward
        (amount uint)
        (blocks-staked uint)
    )
    (/ (* amount blocks-staked (var-get stake-reward-rate)) u10000)
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

(define-public (update-stake-reward-rate (new-rate uint))
    (begin
        (asserts! (is-contract-owner tx-sender) err-owner-only)
        (var-set stake-reward-rate new-rate)
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

(define-read-only (get-stake-info (user principal))
    (map-get? user-stakes user)
)

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-stake-reward-rate)
    (var-get stake-reward-rate)
)

(define-read-only (calculate-current-rewards (user principal))
    (match (map-get? user-stakes user)
        stake-info (let (
                (stake-amount (get amount stake-info))
                (start-block (get start-block stake-info))
                (blocks-staked (- burn-block-height start-block))
            )
            (ok (calculate-stake-reward stake-amount blocks-staked))
        )
        (ok u0)
    )
)
