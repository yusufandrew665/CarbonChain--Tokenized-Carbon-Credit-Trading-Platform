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
(define-constant err-invalid-audit-data (err u109))
(define-constant err-audit-not-found (err u110))
(define-constant err-unauthorized-auditor (err u111))
(define-constant err-inactive-order (err u112))
(define-constant err-order-not-found (err u113))

;; Define data variables
(define-data-var total-credits uint u0)
(define-data-var verification-threshold uint u1000)
(define-data-var credit-price uint u100)
(define-data-var total-retired uint u0)
(define-data-var retirement-certificate-counter uint u0)
(define-data-var total-staked uint u0)
(define-data-var stake-reward-rate uint u5)
(define-data-var audit-log-counter uint u0)
(define-data-var provenance-counter uint u0)
(define-data-var sell-order-counter uint u0)

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
        last-reward-block: uint,
    }
)
(define-map audit-logs
    uint
    {
        credit-id: uint,
        activity-type: (string-ascii 50),
        actor: principal,
        amount: uint,
        timestamp: uint,
        details: (string-ascii 200),
        transaction-hash: (buff 32),
    }
)
(define-map credit-provenance
    uint
    {
        project-name: (string-ascii 100),
        location: (string-ascii 100),
        certification-body: (string-ascii 50),
        methodology: (string-ascii 50),
        vintage-year: uint,
        co2-amount: uint,
        verification-date: uint,
        additional-standards: (list 5 (string-ascii 30)),
    }
)
(define-map impact-verification
    uint
    {
        credit-id: uint,
        impact-type: (string-ascii 50),
        measurement-value: uint,
        unit: (string-ascii 20),
        verifier: principal,
        verification-date: uint,
        evidence-hash: (buff 32),
        confidence-level: uint,
    }
)
(define-map authorized-auditors
    principal
    bool
)
(define-map sell-orders
    uint
    {
        seller: principal,
        price: uint,
        remaining: uint,
        created-at: uint,
        is-active: bool,
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
                last-reward-block: burn-block-height,
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
            (last-reward-block (get last-reward-block stake-info))
            (blocks-locked (- burn-block-height start-block))
            (blocks-for-reward (- burn-block-height last-reward-block))
            (reward-amount (calculate-stake-reward stake-amount blocks-for-reward))
        )
        (begin
            (asserts! (>= blocks-locked lock-period) err-stake-locked)
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

(define-public (claim-staking-rewards)
    (let (
            (stake-info (unwrap! (map-get? user-stakes tx-sender) err-no-stake))
            (last-reward-block (get last-reward-block stake-info))
            (current-block burn-block-height)
            (blocks-elapsed (- current-block last-reward-block))
            (stake-amount (get amount stake-info))
            (reward-amount (if (> blocks-elapsed u0)
                (calculate-stake-reward stake-amount blocks-elapsed)
                u0
            ))
        )
        (begin
            (try! (ft-mint? carbon-credits reward-amount tx-sender))
            (map-set user-stakes tx-sender
                (merge stake-info { last-reward-block: current-block })
            )
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

;; Audit Trail Functions
(define-public (log-credit-activity
        (credit-id uint)
        (activity-type (string-ascii 50))
        (amount uint)
        (details (string-ascii 200))
        (tx-hash (buff 32))
    )
    (let ((log-id (+ (var-get audit-log-counter) u1)))
        (begin
            (asserts! (> credit-id u0) err-invalid-audit-data)
            (asserts! (> (len activity-type) u0) err-invalid-audit-data)
            (map-set audit-logs log-id {
                credit-id: credit-id,
                activity-type: activity-type,
                actor: tx-sender,
                amount: amount,
                timestamp: burn-block-height,
                details: details,
                transaction-hash: tx-hash,
            })
            (var-set audit-log-counter log-id)
            (ok log-id)
        )
    )
)

(define-public (add-provenance-data
        (credit-id uint)
        (project-name (string-ascii 100))
        (location (string-ascii 100))
        (certification-body (string-ascii 50))
        (methodology (string-ascii 50))
        (vintage-year uint)
        (co2-amount uint)
        (additional-standards (list 5 (string-ascii 30)))
    )
    (let ((provenance-id (+ (var-get provenance-counter) u1)))
        (begin
            (asserts! (is-authorized-auditor tx-sender) err-unauthorized-auditor)
            (asserts! (> credit-id u0) err-invalid-audit-data)
            (asserts! (> (len project-name) u0) err-invalid-audit-data)
            (asserts! (> co2-amount u0) err-invalid-audit-data)
            (asserts! (> vintage-year u1990) err-invalid-audit-data)
            (map-set credit-provenance provenance-id {
                project-name: project-name,
                location: location,
                certification-body: certification-body,
                methodology: methodology,
                vintage-year: vintage-year,
                co2-amount: co2-amount,
                verification-date: burn-block-height,
                additional-standards: additional-standards,
            })
            (var-set provenance-counter provenance-id)
            (try! (log-credit-activity credit-id "PROVENANCE_ADDED" co2-amount
                (concat "Provenance data added for project: " project-name)
                0x0000000000000000000000000000000000000000000000000000000000000000
            ))
            (ok provenance-id)
        )
    )
)

(define-public (record-impact-metrics
        (credit-id uint)
        (impact-type (string-ascii 50))
        (measurement-value uint)
        (unit (string-ascii 20))
        (evidence-hash (buff 32))
        (confidence-level uint)
    )
    (let ((impact-id (+ credit-id (* u1000000 burn-block-height))))
        (begin
            (asserts! (is-authorized-auditor tx-sender) err-unauthorized-auditor)
            (asserts! (> credit-id u0) err-invalid-audit-data)
            (asserts! (> (len impact-type) u0) err-invalid-audit-data)
            (asserts! (> measurement-value u0) err-invalid-audit-data)
            (asserts! (<= confidence-level u100) err-invalid-audit-data)
            (map-set impact-verification impact-id {
                credit-id: credit-id,
                impact-type: impact-type,
                measurement-value: measurement-value,
                unit: unit,
                verifier: tx-sender,
                verification-date: burn-block-height,
                evidence-hash: evidence-hash,
                confidence-level: confidence-level,
            })
            (try! (log-credit-activity credit-id "IMPACT_RECORDED" measurement-value
                (concat "Impact metrics recorded: " impact-type)
                evidence-hash
            ))
            (ok impact-id)
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

(define-public (create-sell-order
        (amount uint)
        (price uint)
    )
    (let ((order-id (+ (var-get sell-order-counter) u1)))
        (begin
            (asserts! (> amount u0) err-invalid-amount)
            (asserts! (> price u0) err-invalid-amount)
            (try! (ft-transfer? carbon-credits amount tx-sender (as-contract tx-sender)))
            (map-set sell-orders order-id {
                seller: tx-sender,
                price: price,
                remaining: amount,
                created-at: burn-block-height,
                is-active: true,
            })
            (var-set sell-order-counter order-id)
            (ok order-id)
        )
    )
)

(define-public (fill-sell-order
        (order-id uint)
        (amount uint)
    )
    (let ((order-optional (map-get? sell-orders order-id)))
        (match order-optional
            order (let (
                    (remaining (get remaining order))
                    (price (get price order))
                    (seller (get seller order))
                    (is-active (get is-active order))
                    (purchase-amount amount)
                    (total-cost (* amount price))
                )
                (begin
                    (asserts! is-active err-inactive-order)
                    (asserts! (> purchase-amount u0) err-invalid-amount)
                    (asserts! (<= purchase-amount remaining)
                        err-insufficient-balance
                    )
                    (try! (stx-transfer? total-cost tx-sender seller))
                    (try! (ft-transfer? carbon-credits purchase-amount
                        (as-contract tx-sender) tx-sender
                    ))
                    (let ((new-remaining (- remaining purchase-amount)))
                        (if (> new-remaining u0)
                            (begin
                                (map-set sell-orders order-id
                                    (merge order { remaining: new-remaining })
                                )
                                (ok purchase-amount)
                            )
                            (begin
                                (map-set sell-orders order-id
                                    (merge order {
                                        remaining: u0,
                                        is-active: false,
                                    })
                                )
                                (ok purchase-amount)
                            )
                        )
                    )
                )
            )
            err-order-not-found
        )
    )
)

(define-public (cancel-sell-order (order-id uint))
    (let (
            (order (unwrap! (map-get? sell-orders order-id) err-order-not-found))
            (seller (get seller order))
            (remaining (get remaining order))
            (is-active (get is-active order))
        )
        (begin
            (asserts! (is-eq tx-sender seller) err-unauthorized)
            (asserts! is-active err-inactive-order)
            (if (> remaining u0)
                (begin
                    (try! (ft-transfer? carbon-credits remaining
                        (as-contract tx-sender) seller
                    ))
                    true
                )
                true
            )
            (map-set sell-orders order-id
                (merge order {
                    remaining: u0,
                    is-active: false,
                })
            )
            (ok true)
        )
    )
)

(define-read-only (get-sell-order (order-id uint))
    (map-get? sell-orders order-id)
)

(define-read-only (get-sell-order-count)
    (var-get sell-order-counter)
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

(define-public (set-authorized-auditor
        (address principal)
        (authorized bool)
    )
    (begin
        (asserts! (is-contract-owner tx-sender) err-owner-only)
        (map-set authorized-auditors address authorized)
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
                (last-reward-block (get last-reward-block stake-info))
                (blocks-staked (- burn-block-height last-reward-block))
            )
            (ok (calculate-stake-reward stake-amount blocks-staked))
        )
        (ok u0)
    )
)

;; Audit Trail Read-Only Functions
(define-read-only (get-audit-log (log-id uint))
    (map-get? audit-logs log-id)
)

(define-read-only (get-audit-trail-summary (credit-id uint))
    (ok {
        credit-id: credit-id,
        total-logs: (var-get audit-log-counter),
        message: "Use get-audit-log with specific log IDs to retrieve individual entries",
    })
)

(define-read-only (get-provenance-data (provenance-id uint))
    (map-get? credit-provenance provenance-id)
)

(define-read-only (get-impact-verification (impact-id uint))
    (map-get? impact-verification impact-id)
)

(define-read-only (is-authorized-auditor (address principal))
    (default-to false (map-get? authorized-auditors address))
)

(define-read-only (get-audit-log-count)
    (var-get audit-log-counter)
)

(define-read-only (get-provenance-count)
    (var-get provenance-counter)
)

(define-read-only (generate-compliance-report (credit-id uint))
    (match (map-get? credit-metadata credit-id)
        credit-info (ok {
            credit-id: credit-id,
            owner: (get owner credit-info),
            amount: (get amount credit-info),
            verified: (get verified credit-info),
            created-at: (get timestamp credit-info),
            total-system-logs: (var-get audit-log-counter),
            report-generated-at: burn-block-height,
            compliance-status: (if (get verified credit-info)
                "VERIFIED"
                "PENDING"
            ),
        })
        err-audit-not-found
    )
)

(define-read-only (get-audit-statistics)
    (ok {
        total-audit-logs: (var-get audit-log-counter),
        total-provenance-records: (var-get provenance-counter),
        total-credits: (var-get total-credits),
        total-retired: (var-get total-retired),
        audit-coverage-percentage: (if (> (var-get total-credits) u0)
            (/ (* (var-get audit-log-counter) u100) (var-get total-credits))
            u0
        ),
    })
)
