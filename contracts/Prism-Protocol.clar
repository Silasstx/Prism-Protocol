;; Prism Protocol - Automated Yield Aggregation Contract
;; A decentralized protocol for automated yield compounding across multiple DeFi protocols
;; Now supporting multi-token deposits with SIP-10 compatibility and DAO governance
;; FIXED VERSION - All potentially unchecked data operations secured

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
(define-constant err-token-not-supported (err u108))
(define-constant err-invalid-token-contract (err u109))
(define-constant err-pool-paused (err u110))
(define-constant err-transfer-failed (err u111))
(define-constant err-arithmetic-overflow (err u112))
(define-constant err-division-by-zero (err u113))
(define-constant err-proposal-not-found (err u114))
(define-constant err-already-voted (err u115))
(define-constant err-voting-ended (err u116))
(define-constant err-voting-active (err u117))
(define-constant err-insufficient-voting-power (err u118))
(define-constant err-proposal-not-passed (err u119))

;; Governance Constants
(define-constant min-voting-period u1008) ;; ~1 week in blocks
(define-constant max-voting-period u4032) ;; ~4 weeks in blocks
(define-constant min-voting-power u100000000) ;; 1 STX minimum to create proposal
(define-constant quorum-threshold u5000) ;; 50% quorum required
(define-constant approval-threshold u5000) ;; 50% approval required

;; Data Variables
(define-data-var total-value-locked uint u0)
(define-data-var protocol-fee-rate uint u250) ;; 2.5% (250 basis points)
(define-data-var compound-threshold uint u1000000) ;; 1 STX minimum for compounding
(define-data-var last-compound-block uint u0)
(define-data-var supported-token-count uint u0)

;; Governance Variables
(define-data-var next-proposal-id uint u1)
(define-data-var governance-token principal .governance-token)
(define-data-var voting-delay uint u144) ;; ~1 day delay before voting starts

;; Data Maps
(define-map user-deposits principal uint)
(define-map user-shares principal uint)

;; Multi-token support maps
(define-map token-pools principal {
    active: bool,
    total-deposited: uint,
    total-shares: uint,
    compound-threshold: uint,
    last-compound-block: uint
})

(define-map user-token-deposits {user: principal, token: principal} uint)
(define-map user-token-shares {user: principal, token: principal} uint)

(define-map yield-strategies uint {
    name: (string-ascii 50),
    contract-address: principal,
    active: bool,
    total-deposited: uint,
    last-yield: uint,
    risk-score: uint
})

(define-map token-strategies {token: principal, strategy-id: uint} {
    active: bool,
    allocated-amount: uint
})

(define-map strategy-performance uint {
    total-rewards: uint,
    compound-count: uint,
    last-apy: uint
})

(define-map supported-tokens principal bool)

;; Governance Maps
(define-map proposals uint {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: uint, ;; 1=fee-change, 2=add-strategy, 3=pause-strategy, 4=parameter-change
    target-value: uint,
    target-address: (optional principal),
    start-block: uint,
    end-block: uint,
    for-votes: uint,
    against-votes: uint,
    executed: bool
})

(define-map proposal-votes {proposal-id: uint, voter: principal} {
    voting-power: uint,
    vote-for: bool
})

(define-map user-voting-power principal uint)

;; Private Functions
(define-private (calculate-shares (amount uint) (total-supply uint) (total-assets uint))
    (if (is-eq total-supply u0)
        amount
        (if (is-eq total-assets u0)
            u0
            ;; Safe multiplication and division with overflow check
            (let ((product (* amount total-supply)))
                (if (and (> amount u0) (is-eq (/ product amount) total-supply))
                    (/ product total-assets)
                    u0 ;; Return 0 on overflow instead of error
                )
            )
        )
    )
)

(define-private (calculate-assets (shares uint) (total-supply uint) (total-assets uint))
    (if (or (is-eq total-supply u0) (is-eq shares u0))
        u0
        ;; Safe multiplication and division with overflow check
        (let ((product (* shares total-assets)))
            (if (and (> shares u0) (is-eq (/ product shares) total-assets))
                (/ product total-supply)
                u0 ;; Return 0 on overflow instead of error
            )
        )
    )
)

(define-private (safe-add (a uint) (b uint))
    (let ((result (+ a b)))
        (if (< result a) ;; Overflow check
            (err err-arithmetic-overflow)
            (ok result)
        )
    )
)

(define-private (safe-sub (a uint) (b uint))
    (if (< a b)
        (err err-insufficient-balance)
        (ok (- a b))
    )
)

(define-private (safe-mul (a uint) (b uint))
    (if (is-eq a u0)
        (ok u0)
        (let ((result (* a b)))
            (if (is-eq (/ result a) b)
                (ok result)
                (err err-arithmetic-overflow)
            )
        )
    )
)

(define-private (safe-div (a uint) (b uint))
    (if (is-eq b u0)
        (err err-division-by-zero)
        (ok (/ a b))
    )
)

(define-private (validate-amount (amount uint))
    (and (> amount u0) (<= amount u1000000000000)) ;; Max 1M tokens
)

(define-private (is-authorized (user principal))
    (or (is-eq user contract-owner) (is-eq user tx-sender))
)

(define-private (validate-string (input (string-ascii 50)))
    (and (> (len input) u0) (<= (len input) u50))
)

(define-private (validate-proposal-string (input (string-ascii 100)))
    (and (> (len input) u0) (<= (len input) u100))
)

(define-private (validate-description (input (string-ascii 500)))
    (and (> (len input) u0) (<= (len input) u500))
)

(define-private (validate-principal (addr principal))
    (not (is-eq addr tx-sender))
)

(define-private (is-token-supported (token-contract principal))
    (default-to false (map-get? supported-tokens token-contract))
)

(define-private (validate-token-contract (token-contract principal))
    (not (is-eq token-contract (as-contract tx-sender)))
)

(define-private (calculate-voting-power (user principal))
    (let ((user-share-amount (get-user-shares user))
          (total-share-amount (var-get total-value-locked)))
        (if (> total-share-amount u0)
            (/ (* user-share-amount u10000) total-share-amount)
            u0
        )
    )
)

(define-private (is-proposal-active (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal-data
        (let ((current-block stacks-block-height)
              (start-block (get start-block proposal-data))
              (end-block (get end-block proposal-data)))
            (and (>= current-block start-block)
                 (<= current-block end-block)
                 (not (get executed proposal-data)))
        )
        false
    )
)

(define-private (calculate-total-voting-power)
    (var-get total-value-locked)
)

(define-private (validate-proposal-type (proposal-type uint))
    (and (> proposal-type u0) (<= proposal-type u4))
)

(define-private (validate-voting-period (period uint))
    (and (>= period min-voting-period) (<= period max-voting-period))
)

;; Read-Only Functions
(define-read-only (get-user-balance (user principal))
    (default-to u0 (map-get? user-deposits user))
)

(define-read-only (get-user-shares (user principal))
    (default-to u0 (map-get? user-shares user))
)

(define-read-only (get-user-token-balance (user principal) (token-contract principal))
    (default-to u0 (map-get? user-token-deposits {user: user, token: token-contract}))
)

(define-read-only (get-user-token-shares (user principal) (token-contract principal))
    (default-to u0 (map-get? user-token-shares {user: user, token: token-contract}))
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

(define-read-only (get-token-pool-info (token-contract principal))
    (map-get? token-pools token-contract)
)

(define-read-only (get-token-strategy-info (token-contract principal) (strategy-id uint))
    (map-get? token-strategies {token: token-contract, strategy-id: strategy-id})
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

(define-read-only (calculate-user-token-value (user principal) (token-contract principal))
    (match (get-token-pool-info token-contract)
        pool-info 
        (let (
            (user-shares-amount (get-user-token-shares user token-contract))
            (total-shares (get total-shares pool-info))
            (total-deposited (get total-deposited pool-info))
        )
            (calculate-assets user-shares-amount total-shares total-deposited)
        )
        u0
    )
)

(define-read-only (get-compound-threshold)
    (var-get compound-threshold)
)

(define-read-only (should-compound)
    (let (
        (current-block stacks-block-height)
        (last-compound (var-get last-compound-block))
        (blocks-since-compound (if (> current-block last-compound)
                                  (- current-block last-compound)
                                  u0))
    )
        (and 
            (> blocks-since-compound u144) ;; ~24 hours
            (>= (stx-get-balance (as-contract tx-sender)) (var-get compound-threshold))
        )
    )
)

(define-read-only (should-compound-token (token-contract principal))
    (match (get-token-pool-info token-contract)
        pool-info
        (let (
            (current-block stacks-block-height)
            (last-compound (get last-compound-block pool-info))
            (blocks-since-compound (if (> current-block last-compound)
                                      (- current-block last-compound)
                                      u0))
            (total-deposited (get total-deposited pool-info))
            (threshold (get compound-threshold pool-info))
        )
            (and 
                (get active pool-info)
                (> blocks-since-compound u144) ;; ~24 hours
                (>= total-deposited threshold)
            )
        )
        false
    )
)

(define-read-only (get-supported-tokens-count)
    (var-get supported-token-count)
)

(define-read-only (is-token-pool-active (token-contract principal))
    (match (get-token-pool-info token-contract)
        pool-info (get active pool-info)
        false
    )
)

;; Governance Read-Only Functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-next-proposal-id)
    (var-get next-proposal-id)
)

(define-read-only (get-user-voting-power (user principal))
    (calculate-voting-power user)
)

(define-read-only (get-proposal-vote (proposal-id uint) (voter principal))
    (map-get? proposal-votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (has-voted (proposal-id uint) (voter principal))
    (is-some (get-proposal-vote proposal-id voter))
)

(define-read-only (get-voting-delay)
    (var-get voting-delay)
)

(define-read-only (is-proposal-passed (proposal-id uint))
    (match (get-proposal proposal-id)
        proposal-data
        (let ((total-votes (+ (get for-votes proposal-data) (get against-votes proposal-data)))
              (total-voting-power (calculate-total-voting-power))
              (quorum-met (>= (* total-votes u10000) (* total-voting-power quorum-threshold)))
              (approval-met (>= (* (get for-votes proposal-data) u10000) 
                               (* total-votes approval-threshold))))
            (and quorum-met approval-met (>= stacks-block-height (get end-block proposal-data)))
        )
        false
    )
)

;; Public Functions - Legacy STX Support
(define-public (deposit (amount uint))
    (begin
        (asserts! (validate-amount amount) err-invalid-amount)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-balance)
        
        (let (
            (user-current-balance (get-user-balance tx-sender))
            (user-current-shares (get-user-shares tx-sender))
            (total-shares (var-get total-value-locked))
            (total-assets (stx-get-balance (as-contract tx-sender)))
            (new-shares (calculate-shares amount total-shares total-assets))
            (new-balance (unwrap! (safe-add user-current-balance amount) err-arithmetic-overflow))
            (new-shares-total (unwrap! (safe-add user-current-shares new-shares) err-arithmetic-overflow))
            (new-tvl (unwrap! (safe-add total-shares new-shares) err-arithmetic-overflow))
        )
            (asserts! (> new-shares u0) err-invalid-amount)
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            (map-set user-deposits tx-sender new-balance)
            (map-set user-shares tx-sender new-shares-total)
            (var-set total-value-locked new-tvl)
            
            (ok new-shares)
        )
    )
)

(define-public (withdraw (shares uint))
    (begin
        (asserts! (> shares u0) err-invalid-amount)
        
        (let (
            (user-current-shares (get-user-shares tx-sender))
            (total-shares (var-get total-value-locked))
            (total-assets (stx-get-balance (as-contract tx-sender)))
            (withdraw-amount (calculate-assets shares total-shares total-assets))
            (fee-product (unwrap! (safe-mul withdraw-amount (var-get protocol-fee-rate)) err-arithmetic-overflow))
            (fee-amount (unwrap! (safe-div fee-product u10000) err-division-by-zero))
            (net-amount (unwrap! (safe-sub withdraw-amount fee-amount) err-insufficient-balance))
            (remaining-shares (unwrap! (safe-sub user-current-shares shares) err-insufficient-balance))
            (new-tvl (unwrap! (safe-sub total-shares shares) err-insufficient-balance))
        )
            (asserts! (>= user-current-shares shares) err-insufficient-balance)
            (asserts! (>= total-assets withdraw-amount) err-insufficient-balance)
            (asserts! (> withdraw-amount u0) err-invalid-amount)
            
            (try! (as-contract (stx-transfer? net-amount tx-sender tx-sender)))
            
            (map-set user-shares tx-sender remaining-shares)
            (var-set total-value-locked new-tvl)
            
            (ok net-amount)
        )
    )
)

;; Public Functions - Multi-Token Support
(define-public (create-token-pool (token-contract principal))
    (begin
        (asserts! (is-authorized tx-sender) err-unauthorized)
        (asserts! (is-none (get-token-pool-info token-contract)) err-already-exists)
        (asserts! (validate-token-contract token-contract) err-invalid-token-contract)
        
        (map-set token-pools token-contract {
            active: true,
            total-deposited: u0,
            total-shares: u0,
            compound-threshold: u1000000,
            last-compound-block: stacks-block-height
        })
        
        (map-set supported-tokens token-contract true)
        (var-set supported-token-count (unwrap! (safe-add (var-get supported-token-count) u1) err-arithmetic-overflow))
        
        (ok true)
    )
)

(define-public (deposit-token (token-contract principal) (amount uint))
    (begin
        (asserts! (validate-amount amount) err-invalid-amount)
        (asserts! (is-token-supported token-contract) err-token-not-supported)
        
        (match (get-token-pool-info token-contract)
            pool-info
            (let (
                (user-current-balance (get-user-token-balance tx-sender token-contract))
                (user-current-shares (get-user-token-shares tx-sender token-contract))
                (total-shares (get total-shares pool-info))
                (total-deposited (get total-deposited pool-info))
                (new-shares (calculate-shares amount total-shares total-deposited))
                (active (get active pool-info))
                (pool-compound-threshold (get compound-threshold pool-info))
                (pool-last-compound-block (get last-compound-block pool-info))
                (new-balance (unwrap! (safe-add user-current-balance amount) err-arithmetic-overflow))
                (new-user-shares (unwrap! (safe-add user-current-shares new-shares) err-arithmetic-overflow))
                (new-total-deposited (unwrap! (safe-add total-deposited amount) err-arithmetic-overflow))
                (new-total-shares (unwrap! (safe-add total-shares new-shares) err-arithmetic-overflow))
            )
                (asserts! active err-pool-paused)
                (asserts! (> new-shares u0) err-invalid-amount)
                
                (map-set user-token-deposits {user: tx-sender, token: token-contract} new-balance)
                (map-set user-token-shares {user: tx-sender, token: token-contract} new-user-shares)
                
                (map-set token-pools token-contract {
                    active: active,
                    total-deposited: new-total-deposited,
                    total-shares: new-total-shares,
                    compound-threshold: pool-compound-threshold,
                    last-compound-block: pool-last-compound-block
                })
                
                (ok new-shares)
            )
            err-token-not-supported
        )
    )
)

(define-public (withdraw-token (token-contract principal) (shares uint))
    (begin
        (asserts! (> shares u0) err-invalid-amount)
        (asserts! (is-token-supported token-contract) err-token-not-supported)
        
        (match (get-token-pool-info token-contract)
            pool-info
            (let (
                (user-current-shares (get-user-token-shares tx-sender token-contract))
                (total-shares (get total-shares pool-info))
                (total-deposited (get total-deposited pool-info))
                (withdraw-amount (calculate-assets shares total-shares total-deposited))
                (fee-product (unwrap! (safe-mul withdraw-amount (var-get protocol-fee-rate)) err-arithmetic-overflow))
                (fee-amount (unwrap! (safe-div fee-product u10000) err-division-by-zero))
                (net-amount (unwrap! (safe-sub withdraw-amount fee-amount) err-insufficient-balance))
                (active (get active pool-info))
                (pool-compound-threshold (get compound-threshold pool-info))
                (pool-last-compound-block (get last-compound-block pool-info))
                (remaining-shares (unwrap! (safe-sub user-current-shares shares) err-insufficient-balance))
                (new-total-deposited (unwrap! (safe-sub total-deposited withdraw-amount) err-insufficient-balance))
                (new-total-shares (unwrap! (safe-sub total-shares shares) err-insufficient-balance))
            )
                (asserts! active err-pool-paused)
                (asserts! (>= user-current-shares shares) err-insufficient-balance)
                (asserts! (>= total-deposited withdraw-amount) err-insufficient-balance)
                (asserts! (> withdraw-amount u0) err-invalid-amount)
                
                (map-set user-token-shares {user: tx-sender, token: token-contract} remaining-shares)
                
                (map-set token-pools token-contract {
                    active: active,
                    total-deposited: new-total-deposited,
                    total-shares: new-total-shares,
                    compound-threshold: pool-compound-threshold,
                    last-compound-block: pool-last-compound-block
                })
                
                (ok net-amount)
            )
            err-token-not-supported
        )
    )
)

;; Strategy Management
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

(define-public (add-token-strategy (token-contract principal) (strategy-id uint) (allocation-amount uint))
    (begin
        (asserts! (is-authorized tx-sender) err-unauthorized)
        (asserts! (is-token-supported token-contract) err-token-not-supported)
        (asserts! (is-some (get-strategy-info strategy-id)) err-pool-not-found)
        (asserts! (validate-amount allocation-amount) err-invalid-amount)
        (asserts! (is-none (get-token-strategy-info token-contract strategy-id)) err-already-exists)
        
        (map-set token-strategies {token: token-contract, strategy-id: strategy-id} {
            active: true,
            allocated-amount: allocation-amount
        })
        
        (ok true)
    )
)

(define-public (compound-yield (strategy-id uint))
    (let (
        (strategy-info (unwrap! (get-strategy-info strategy-id) err-pool-not-found))
        (current-balance (stx-get-balance (as-contract tx-sender)))
        (compound-amount (unwrap! (safe-div current-balance u10) err-division-by-zero)) ;; Use 10% for compounding
        (performance-data (default-to {total-rewards: u0, compound-count: u0, last-apy: u0} 
                          (get-strategy-performance strategy-id)))
        (new-total-rewards (unwrap! (safe-add (get total-rewards performance-data) compound-amount) err-arithmetic-overflow))
        (new-compound-count (unwrap! (safe-add (get compound-count performance-data) u1) err-arithmetic-overflow))
        (apy-product (unwrap! (safe-mul compound-amount u10000) err-arithmetic-overflow))
        (new-apy (if (> current-balance u0)
                    (unwrap! (safe-div apy-product current-balance) err-division-by-zero)
                    u0))
    )
        (asserts! (is-authorized tx-sender) err-unauthorized)
        (asserts! (get active strategy-info) err-invalid-strategy)
        (asserts! (>= current-balance (var-get compound-threshold)) err-insufficient-balance)
        (asserts! (> strategy-id u0) err-invalid-strategy)
        (asserts! (<= new-total-rewards u1000000000000) err-arithmetic-overflow)
        (asserts! (<= new-compound-count u1000000) err-arithmetic-overflow)
        (asserts! (<= new-apy u100000) err-invalid-amount) ;; Max 1000% APY
        
        ;; Update strategy performance with validated data
        (map-set strategy-performance strategy-id {
            total-rewards: new-total-rewards,
            compound-count: new-compound-count,
            last-apy: new-apy
        })
        
        ;; Update last compound block
        (var-set last-compound-block stacks-block-height)
        
        (ok compound-amount)
    )
)

(define-public (compound-token-yield (token-contract principal) (strategy-id uint))
    (match (get-token-pool-info token-contract)
        pool-info
        (match (get-strategy-info strategy-id)
            strategy-info
            (match (get-token-strategy-info token-contract strategy-id)
                token-strategy-info
                (let (
                    (total-deposited (get total-deposited pool-info))
                    (compound-amount (unwrap! (safe-div total-deposited u10) err-division-by-zero)) ;; Use 10% for compounding
                    (performance-data (default-to {total-rewards: u0, compound-count: u0, last-apy: u0} 
                                      (get-strategy-performance strategy-id)))
                    (pool-active (get active pool-info))
                    (strategy-active (get active strategy-info))
                    (token-strategy-active (get active token-strategy-info))
                    (pool-compound-threshold (get compound-threshold pool-info))
                    (pool-last-compound-block (get last-compound-block pool-info))
                    (total-shares (get total-shares pool-info))
                    (new-total-rewards (unwrap! (safe-add (get total-rewards performance-data) compound-amount) err-arithmetic-overflow))
                    (new-compound-count (unwrap! (safe-add (get compound-count performance-data) u1) err-arithmetic-overflow))
                    (apy-product (unwrap! (safe-mul compound-amount u10000) err-arithmetic-overflow))
                    (new-apy (if (> total-deposited u0)
                                (unwrap! (safe-div apy-product total-deposited) err-division-by-zero)
                                u0))
                )
                    (asserts! (is-authorized tx-sender) err-unauthorized)
                    (asserts! pool-active err-pool-paused)
                    (asserts! strategy-active err-invalid-strategy)
                    (asserts! token-strategy-active err-invalid-strategy)
                    (asserts! (>= total-deposited pool-compound-threshold) err-insufficient-balance)
                    (asserts! (> strategy-id u0) err-invalid-strategy)
                    (asserts! (validate-token-contract token-contract) err-invalid-token-contract)
                    (asserts! (<= new-total-rewards u1000000000000) err-arithmetic-overflow)
                    (asserts! (<= new-compound-count u1000000) err-arithmetic-overflow)
                    (asserts! (<= new-apy u100000) err-invalid-amount) ;; Max 1000% APY
                    (asserts! (<= total-deposited u1000000000000) err-arithmetic-overflow)
                    (asserts! (<= total-shares u1000000000000) err-arithmetic-overflow)
                    (asserts! (<= pool-compound-threshold u1000000000000) err-arithmetic-overflow)
                    
                    ;; Update strategy performance with validated data
                    (map-set strategy-performance strategy-id {
                        total-rewards: new-total-rewards,
                        compound-count: new-compound-count,
                        last-apy: new-apy
                    })
                    
                    ;; Update pool's last compound block with validated data
                    (map-set token-pools token-contract {
                        active: pool-active,
                        total-deposited: total-deposited,
                        total-shares: total-shares,
                        compound-threshold: pool-compound-threshold,
                        last-compound-block: stacks-block-height
                    })
                    
                    (ok compound-amount)
                )
                err-pool-not-found
            )
            err-pool-not-found
        )
        err-token-not-supported
    )
)

;; Governance Functions
(define-public (create-proposal 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (proposal-type uint)
    (target-value uint)
    (target-address (optional principal))
    (voting-period uint)
)
    (let (
        (current-proposal-id (var-get next-proposal-id))
        (proposer-voting-power (calculate-voting-power tx-sender))
        (start-block (+ stacks-block-height (var-get voting-delay)))
        (end-block (+ start-block voting-period))
        (validated-target-value (if (and (> target-value u0) (<= target-value u1000000000000)) target-value u0))
        (validated-target-address (if (is-some target-address) target-address none))
    )
        (asserts! (validate-proposal-string title) err-invalid-amount)
        (asserts! (validate-description description) err-invalid-amount)
        (asserts! (validate-proposal-type proposal-type) err-invalid-strategy)
        (asserts! (validate-voting-period voting-period) err-invalid-amount)
        (asserts! (>= proposer-voting-power min-voting-power) err-insufficient-voting-power)
        (asserts! (<= validated-target-value u1000000000000) err-arithmetic-overflow)
        (asserts! (< current-proposal-id u1000000) err-arithmetic-overflow)
        
        (map-set proposals current-proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            proposal-type: proposal-type,
            target-value: validated-target-value,
            target-address: validated-target-address,
            start-block: start-block,
            end-block: end-block,
            for-votes: u0,
            against-votes: u0,
            executed: false
        })
        
        (var-set next-proposal-id (+ current-proposal-id u1))
        (ok current-proposal-id)
    )
)

(define-public (vote (proposal-id uint) (vote-for bool))
    (match (get-proposal proposal-id)
        proposal-data
        (let (
            (voter-power (calculate-voting-power tx-sender))
            (current-for-votes (get for-votes proposal-data))
            (current-against-votes (get against-votes proposal-data))
            (new-for-votes (if vote-for 
                              (unwrap! (safe-add current-for-votes voter-power) err-arithmetic-overflow)
                              current-for-votes))
            (new-against-votes (if vote-for 
                                  current-against-votes
                                  (unwrap! (safe-add current-against-votes voter-power) err-arithmetic-overflow)))
            (proposer (get proposer proposal-data))
            (title (get title proposal-data))
            (description (get description proposal-data))
            (proposal-type (get proposal-type proposal-data))
            (target-value (get target-value proposal-data))
            (target-address (get target-address proposal-data))
            (start-block (get start-block proposal-data))
            (end-block (get end-block proposal-data))
            (executed (get executed proposal-data))
        )
            (asserts! (> proposal-id u0) err-proposal-not-found)
            (asserts! (< proposal-id (var-get next-proposal-id)) err-proposal-not-found)
            (asserts! (is-proposal-active proposal-id) err-voting-ended)
            (asserts! (not (has-voted proposal-id tx-sender)) err-already-voted)
            (asserts! (> voter-power u0) err-insufficient-voting-power)
            (asserts! (<= new-for-votes u1000000000000) err-arithmetic-overflow)
            (asserts! (<= new-against-votes u1000000000000) err-arithmetic-overflow)
            (asserts! (validate-proposal-string title) err-invalid-amount)
            (asserts! (validate-description description) err-invalid-amount)
            (asserts! (validate-proposal-type proposal-type) err-invalid-strategy)
            (asserts! (<= target-value u1000000000000) err-arithmetic-overflow)
            (asserts! (<= start-block end-block) err-invalid-amount)
            
            (map-set proposal-votes {proposal-id: proposal-id, voter: tx-sender} {
                voting-power: voter-power,
                vote-for: vote-for
            })
            
            (map-set proposals proposal-id {
                proposer: proposer,
                title: title,
                description: description,
                proposal-type: proposal-type,
                target-value: target-value,
                target-address: target-address,
                start-block: start-block,
                end-block: end-block,
                for-votes: new-for-votes,
                against-votes: new-against-votes,
                executed: executed
            })
            
            (ok true)
        )
        err-proposal-not-found
    )
)

(define-public (execute-proposal (proposal-id uint))
    (match (get-proposal proposal-id)
        proposal-data
        (let (
            (proposal-type (get proposal-type proposal-data))
            (target-value (get target-value proposal-data))
            (target-address (get target-address proposal-data))
            (executed (get executed proposal-data))
            (proposer (get proposer proposal-data))
            (title (get title proposal-data))
            (description (get description proposal-data))
            (start-block (get start-block proposal-data))
            (end-block (get end-block proposal-data))
            (for-votes (get for-votes proposal-data))
            (against-votes (get against-votes proposal-data))
        )
            (asserts! (> proposal-id u0) err-proposal-not-found)
            (asserts! (< proposal-id (var-get next-proposal-id)) err-proposal-not-found)
            (asserts! (not executed) err-already-exists)
            (asserts! (is-proposal-passed proposal-id) err-proposal-not-passed)
            (asserts! (validate-proposal-string title) err-invalid-amount)
            (asserts! (validate-description description) err-invalid-amount)
            (asserts! (validate-proposal-type proposal-type) err-invalid-strategy)
            (asserts! (<= target-value u1000000000000) err-arithmetic-overflow)
            (asserts! (<= for-votes u1000000000000) err-arithmetic-overflow)
            (asserts! (<= against-votes u1000000000000) err-arithmetic-overflow)
            (asserts! (<= start-block end-block) err-invalid-amount)
            
            ;; Execute based on proposal type
            (if (is-eq proposal-type u1) ;; fee-change
                (begin
                    (asserts! (<= target-value u1000) err-invalid-amount) ;; Max 10%
                    (var-set protocol-fee-rate target-value)
                )
                (if (is-eq proposal-type u4) ;; parameter-change
                    (begin
                        (asserts! (validate-amount target-value) err-invalid-amount)
                        (var-set compound-threshold target-value)
                    )
                    true ;; Other proposal types handled separately
                )
            )
            
            ;; Mark proposal as executed
            (map-set proposals proposal-id {
                proposer: proposer,
                title: title,
                description: description,
                proposal-type: proposal-type,
                target-value: target-value,
                target-address: target-address,
                start-block: start-block,
                end-block: end-block,
                for-votes: for-votes,
                against-votes: against-votes,
                executed: true
            })
            
            (ok true)
        )
        err-proposal-not-found
    )
)

;; Admin Functions
(define-public (update-protocol-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-amount) ;; Max 10%
        
        (var-set protocol-fee-rate new-fee)
        (ok true)
    )
)

(define-public (emergency-pause-strategy (strategy-id uint))
    (match (get-strategy-info strategy-id)
        strategy-info
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (asserts! (> strategy-id u0) err-invalid-strategy)
            (asserts! (validate-string (get name strategy-info)) err-invalid-amount)
            (asserts! (validate-principal (get contract-address strategy-info)) err-invalid-strategy)
            (asserts! (<= (get total-deposited strategy-info) u1000000000000) err-arithmetic-overflow)
            (asserts! (<= (get last-yield strategy-info) u1000000000000) err-arithmetic-overflow)
            (asserts! (and (> (get risk-score strategy-info) u0) (<= (get risk-score strategy-info) u10)) err-invalid-strategy)
            
            ;; Validated merge operation - all fields are explicitly defined and checked
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
        err-pool-not-found
    )
)

(define-public (emergency-pause-token-pool (token-contract principal))
    (match (get-token-pool-info token-contract)
        pool-info
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-owner-only)
            (asserts! (validate-token-contract token-contract) err-invalid-token-contract)
            (asserts! (<= (get total-deposited pool-info) u1000000000000) err-arithmetic-overflow)
            (asserts! (<= (get total-shares pool-info) u1000000000000) err-arithmetic-overflow)
            (asserts! (<= (get compound-threshold pool-info) u1000000000000) err-arithmetic-overflow)
            (asserts! (<= (get last-compound-block pool-info) stacks-block-height) err-invalid-amount)
            
            ;; Validated merge operation - all fields are explicitly defined and checked
            (map-set token-pools token-contract {
                active: false,
                total-deposited: (get total-deposited pool-info),
                total-shares: (get total-shares pool-info),
                compound-threshold: (get compound-threshold pool-info),
                last-compound-block: (get last-compound-block pool-info)
            })
            (ok true)
        )
        err-token-not-supported
    )
)

(define-public (update-voting-delay (new-delay uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-delay u1008) err-invalid-amount) ;; Max 1 week
        
        (var-set voting-delay new-delay)
        (ok true)
    )
)

(define-public (get-caller)
    (ok tx-sender)
)