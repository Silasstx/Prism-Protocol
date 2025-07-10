;; Prism Protocol - Automated Yield Aggregation Contract
;; A decentralized protocol for automated yield compounding across multiple DeFi protocols

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-pool-not-found (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-strategy (err u106))
(define-constant err-compound-failed (err u107))

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var protocol-fee-rate uint u250) ;; 2.5% (250 basis points)
(define-data-var compound-threshold uint u1000000) ;; 1 STX minimum for compounding
(define-data-var last-compound-block uint u0)

;; Data Maps
(define-map user-deposits principal uint)
(define-map user-shares principal uint)
(define-map yield-strategies uint {
    name: (string-ascii 50),
    contract-address: principal,
    active: bool,
    total-deposited: uint,
    last-yield: uint,
    risk-score: uint
})

(define-map strategy-performance uint {
    total-rewards: uint,
    compound-count: uint,
    last-apy: uint
})

;; Private Functions
(define-private (calculate-shares (amount uint) (total-supply uint) (total-assets uint))
    (if (is-eq total-supply u0)
        amount
        (/ (* amount total-supply) total-assets)
    )
)

(define-private (calculate-assets (shares uint) (total-supply uint) (total-assets uint))
    (if (is-eq total-supply u0)
        u0
        (/ (* shares total-assets) total-supply)
    )
)

(define-private (validate-amount (amount uint))
    (and (> amount u0) (<= amount u1000000000000)) ;; Max 1M STX
)

(define-private (is-authorized (user principal))
    (or (is-eq user contract-owner) (is-eq user tx-sender))
)

(define-private (validate-string (input (string-ascii 50)))
    (and (> (len input) u0) (<= (len input) u50))
)

(define-private (validate-principal (addr principal))
    (not (is-eq addr tx-sender)) ;; Ensure it's not the same as sender
)

;; Read-Only Functions
(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? user-deposits user))
)

(define-read-only (get-user-shares (user principal))
    (default-to u0 (map-get? user-shares user))
)

(define-read-only (get-total-value-locked)
    (var-get total-value-locked)
)

(define-read-only (get-protocol-fee-rate)
    (var-get protocol-fee-rate)
)

(define-read-only (get-strategy-info (strategy-id uint))
    (map-get? yield-strategies strategy-id)
)

(define-read-only (get-strategy-performance (strategy-id uint))
    (map-get? strategy-performance strategy-id)
)

(define-read-only (calculate-user-value (user principal))
    (let (
        (user-shares-amount (get-user-shares user))
        (total-shares (var-get total-value-locked))
        (total-assets (stx-get-balance (as-contract tx-sender)))
    )
        (calculate-assets user-shares-amount total-shares total-assets)
    )
)

(define-read-only (get-compound-threshold)
    (var-get compound-threshold)
)

(define-read-only (should-compound)
    (let (
        (current-block stacks-block-height)
        (last-compound (var-get last-compound-block))
        (blocks-since-compound (- current-block last-compound))
    )
        (and 
            (> blocks-since-compound u144) ;; ~24 hours
            (>= (stx-get-balance (as-contract tx-sender)) (var-get compound-threshold))
        )
    )
)

;; Public Functions
(define-public (deposit (amount uint))
    (let (
        (user-current-balance (get-user-balance tx-sender))
        (user-current-shares (get-user-shares tx-sender))
        (total-shares (var-get total-value-locked))
        (total-assets (stx-get-balance (as-contract tx-sender)))
        (new-shares (calculate-shares amount total-shares total-assets))
    )
        (asserts! (validate-amount amount) err-invalid-amount)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-balance)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set user-deposits tx-sender (+ user-current-balance amount))
        (map-set user-shares tx-sender (+ user-current-shares new-shares))
        (var-set total-value-locked (+ total-shares new-shares))
        
        (ok new-shares)
    )
)

(define-public (withdraw (shares uint))
    (let (
        (user-current-shares (get-user-shares tx-sender))
        (total-shares (var-get total-value-locked))
        (total-assets (stx-get-balance (as-contract tx-sender)))
        (withdraw-amount (calculate-assets shares total-shares total-assets))
        (fee-amount (/ (* withdraw-amount (var-get protocol-fee-rate)) u10000))
        (net-amount (- withdraw-amount fee-amount))
    )
        (asserts! (> shares u0) err-invalid-amount)
        (asserts! (>= user-current-shares shares) err-insufficient-balance)
        (asserts! (>= total-assets withdraw-amount) err-insufficient-balance)
        
        (try! (as-contract (stx-transfer? net-amount tx-sender (unwrap-panic (get-caller)))))
        
        (map-set user-shares tx-sender (- user-current-shares shares))
        (var-set total-value-locked (- total-shares shares))
        
        (ok net-amount)
    )
)

(define-public (add-yield-strategy (strategy-id uint) (name (string-ascii 50)) (contract-addr principal) (risk-score uint))
    (begin
        (asserts! (is-authorized tx-sender) err-unauthorized)
        (asserts! (is-none (get-strategy-info strategy-id)) err-already-exists)
        (asserts! (and (> risk-score u0) (<= risk-score u10)) err-invalid-strategy)
        (asserts! (validate-string name) err-invalid-amount)
        (asserts! (validate-principal contract-addr) err-invalid-strategy)
        
        (map-set yield-strategies strategy-id {
            name: name,
            contract-address: contract-addr,
            active: true,
            total-deposited: u0,
            last-yield: u0,
            risk-score: risk-score
        })
        
        (map-set strategy-performance strategy-id {
            total-rewards: u0,
            compound-count: u0,
            last-apy: u0
        })
        
        (ok true)
    )
)

(define-public (compound-yield (strategy-id uint))
    (let (
        (strategy-info (unwrap! (get-strategy-info strategy-id) err-pool-not-found))
        (current-balance (stx-get-balance (as-contract tx-sender)))
        (compound-amount (/ current-balance u10)) ;; Use 10% for compounding
        (performance-data (default-to {total-rewards: u0, compound-count: u0, last-apy: u0} 
                          (get-strategy-performance strategy-id)))
    )
        (asserts! (is-authorized tx-sender) err-unauthorized)
        (asserts! (get active strategy-info) err-invalid-strategy)
        (asserts! (>= current-balance (var-get compound-threshold)) err-insufficient-balance)
        
        ;; Update strategy performance
        (map-set strategy-performance strategy-id {
            total-rewards: (+ (get total-rewards performance-data) compound-amount),
            compound-count: (+ (get compound-count performance-data) u1),
            last-apy: (/ (* compound-amount u10000) current-balance) ;; Simple APY calculation
        })
        
        ;; Update last compound block
        (var-set last-compound-block stacks-block-height)
        
        (ok compound-amount)
    )
)

(define-public (update-protocol-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-amount) ;; Max 10%
        
        (var-set protocol-fee-rate new-fee)
        (ok true)
    )
)

(define-public (emergency-pause-strategy (strategy-id uint))
    (let (
        (strategy-info (unwrap! (get-strategy-info strategy-id) err-pool-not-found))
        (validated-strategy (asserts! (is-some (get-strategy-info strategy-id)) err-pool-not-found))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set yield-strategies strategy-id {
            name: (get name strategy-info),
            contract-address: (get contract-address strategy-info),
            active: false,
            total-deposited: (get total-deposited strategy-info),
            last-yield: (get last-yield strategy-info),
            risk-score: (get risk-score strategy-info)
        })
        (ok true)
    )
)

(define-public (get-caller)
    (ok tx-sender)
)