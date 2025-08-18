(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_PROPOSAL_EXPIRED (err u105))
(define-constant ERR_ALREADY_VOTED (err u106))
(define-constant ERR_NOT_MEMBER (err u107))
(define-constant ERR_INVALID_RATING (err u108))
(define-constant ERR_ALREADY_RATED (err u109))
(define-constant ERR_QUALITY_TOO_LOW (err u110))
(define-constant ERR_INSUFFICIENT_SESSIONS (err u111))
(define-constant ERR_ZONE_NOT_FOUND (err u112))
(define-constant ERR_ZONE_EXISTS (err u113))
(define-constant ERR_INVALID_COORDINATES (err u114))
(define-constant ERR_NOT_ZONE_ADMIN (err u115))
(define-constant ERR_ZONE_INACTIVE (err u116))

(define-data-var next-node-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var membership-fee uint u1000000)
(define-data-var proposal-duration uint u1440)
(define-data-var min-quality-score uint u50)
(define-data-var quality-bonus-multiplier uint u20)
(define-data-var next-zone-id uint u1)
(define-data-var default-zone-incentive uint u15)
(define-data-var max-nodes-per-zone uint u50)

(define-map wifi-nodes
    { node-id: uint }
    {
        owner: principal,
        location: (string-ascii 100),
        bandwidth: uint,
        uptime: uint,
        earnings: uint,
        active: bool,
        created-at: uint,
        quality-score: uint,
        total-sessions: uint,
        total-ratings: uint,
        rating-sum: uint,
        reliability-score: uint,
        zone-id: uint
    }
)

(define-map dao-members
    { member: principal }
    {
        stake: uint,
        joined-at: uint,
        voting-power: uint,
        total-earned: uint
    }
)

(define-map proposals
    { proposal-id: uint }
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        amount: uint,
        recipient: principal,
        votes-for: uint,
        votes-against: uint,
        created-at: uint,
        expires-at: uint,
        executed: bool
    }
)

(define-map votes
    { proposal-id: uint, voter: principal }
    { vote: bool, power: uint }
)

(define-map node-usage
    { node-id: uint, user: principal }
    { data-used: uint, last-session: uint, total-paid: uint }
)

(define-map node-ratings
    { node-id: uint, rater: principal }
    { rating: uint, session-count: uint, created-at: uint }
)

(define-map quality-thresholds
    { threshold-level: uint }
    { min-score: uint, bonus-percentage: uint, max-visible: bool }
)

(define-map coverage-zones
    { zone-id: uint }
    {
        name: (string-ascii 50),
        latitude: uint,
        longitude: uint,
        radius: uint,
        admin: principal,
        active: bool,
        node-count: uint,
        total-bandwidth: uint,
        avg-quality: uint,
        coverage-bonus: uint,
        created-at: uint
    }
)

(define-map zone-nodes
    { zone-id: uint, node-id: uint }
    { assigned-at: uint, contribution-score: uint }
)

(define-map zone-coverage-stats
    { zone-id: uint }
    {
        peak-usage: uint,
        avg-usage: uint,
        coverage-density: uint,
        last-updated: uint,
        incentive-multiplier: uint
    }
)

(define-public (join-dao)
    (let
        (
            (membership-cost (var-get membership-fee))
            (member-data (default-to 
                { stake: u0, joined-at: u0, voting-power: u0, total-earned: u0 }
                (map-get? dao-members { member: tx-sender })
            ))
        )
        (asserts! (>= (stx-get-balance tx-sender) membership-cost) ERR_INSUFFICIENT_FUNDS)
        (try! (stx-transfer? membership-cost tx-sender (as-contract tx-sender)))
        (map-set dao-members
            { member: tx-sender }
            {
                stake: (+ (get stake member-data) membership-cost),
                joined-at: (if (is-eq (get joined-at member-data) u0) stacks-block-height (get joined-at member-data)),
                voting-power: (+ (get voting-power member-data) u1),
                total-earned: (get total-earned member-data)
            }
        )
        (ok true)
    )
)

(define-public (register-wifi-node (location (string-ascii 100)) (bandwidth uint) (zone-id uint))
    (let
        (
            (node-id (var-get next-node-id))
            (member-data (map-get? dao-members { member: tx-sender }))
            (zone-data (map-get? coverage-zones { zone-id: zone-id }))
        )
        (asserts! (is-some member-data) ERR_NOT_MEMBER)
        (asserts! (> bandwidth u0) ERR_INVALID_AMOUNT)
        (asserts! (if (> zone-id u0) (is-some zone-data) true) ERR_ZONE_NOT_FOUND)
        (asserts! (if (> zone-id u0) (get active (unwrap-panic zone-data)) true) ERR_ZONE_INACTIVE)
        
        (map-set wifi-nodes
            { node-id: node-id }
            {
                owner: tx-sender,
                location: location,
                bandwidth: bandwidth,
                uptime: u0,
                earnings: u0,
                active: true,
                created-at: stacks-block-height,
                quality-score: u75,
                total-sessions: u0,
                total-ratings: u0,
                rating-sum: u0,
                reliability-score: u100,
                zone-id: zone-id
            }
        )
        
        (if (> zone-id u0)
            (begin
                (map-set zone-nodes
                    { zone-id: zone-id, node-id: node-id }
                    { assigned-at: stacks-block-height, contribution-score: u50 }
                )
                (try! (update-zone-stats zone-id))
                true
            )
            true
        )
        
        (var-set next-node-id (+ node-id u1))
        (ok node-id)
    )
)

(define-public (use-wifi (node-id uint) (data-amount uint))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (usage-cost (* data-amount u10))
            (owner-share (* usage-cost u70))
            (dao-share (* usage-cost u30))
            (current-usage (default-to 
                { data-used: u0, last-session: u0, total-paid: u0 }
                (map-get? node-usage { node-id: node-id, user: tx-sender })
            ))
        )
        (asserts! (get active node-data) ERR_NOT_FOUND)
        (asserts! (>= (stx-get-balance tx-sender) usage-cost) ERR_INSUFFICIENT_FUNDS)
        (try! (stx-transfer? (/ owner-share u100) tx-sender (get owner node-data)))
        (try! (stx-transfer? (/ dao-share u100) tx-sender (as-contract tx-sender)))
        
        (map-set wifi-nodes
            { node-id: node-id }
            (merge node-data { 
                earnings: (+ (get earnings node-data) (/ owner-share u100)),
                uptime: (+ (get uptime node-data) u1),
                total-sessions: (+ (get total-sessions node-data) u1)
            })
        )
        
        (map-set node-usage
            { node-id: node-id, user: tx-sender }
            {
                data-used: (+ (get data-used current-usage) data-amount),
                last-session: stacks-block-height,
                total-paid: (+ (get total-paid current-usage) usage-cost)
            }
        )
        (ok true)
    )
)

(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (amount uint) (recipient principal))
    (let
        (
            (proposal-id (var-get next-proposal-id))
            (member-data (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_MEMBER))
        )
        (asserts! (>= (get voting-power member-data) u1) ERR_UNAUTHORIZED)
        (map-set proposals
            { proposal-id: proposal-id }
            {
                proposer: tx-sender,
                title: title,
                description: description,
                amount: amount,
                recipient: recipient,
                votes-for: u0,
                votes-against: u0,
                created-at: stacks-block-height,
                expires-at: (+ stacks-block-height (var-get proposal-duration)),
                executed: false
            }
        )
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
            (member-data (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_MEMBER))
            (existing-vote (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
            (voting-power (get voting-power member-data))
        )
        (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
        (asserts! (< stacks-block-height (get expires-at proposal-data)) ERR_PROPOSAL_EXPIRED)
        
        (map-set votes
            { proposal-id: proposal-id, voter: tx-sender }
            { vote: vote-for, power: voting-power }
        )
        
        (map-set proposals
            { proposal-id: proposal-id }
            (merge proposal-data {
                votes-for: (if vote-for (+ (get votes-for proposal-data) voting-power) (get votes-for proposal-data)),
                votes-against: (if vote-for (get votes-against proposal-data) (+ (get votes-against proposal-data) voting-power))
            })
        )
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let
        (
            (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_NOT_FOUND))
            (total-votes (+ (get votes-for proposal-data) (get votes-against proposal-data)))
        )
        (asserts! (>= stacks-block-height (get expires-at proposal-data)) ERR_PROPOSAL_EXPIRED)
        (asserts! (not (get executed proposal-data)) ERR_ALREADY_EXISTS)
        (asserts! (> (get votes-for proposal-data) (get votes-against proposal-data)) ERR_UNAUTHORIZED)
        
        (if (> (get amount proposal-data) u0)
            (try! (as-contract (stx-transfer? (get amount proposal-data) tx-sender (get recipient proposal-data))))
            true
        )
        
        (map-set proposals
            { proposal-id: proposal-id }
            (merge proposal-data { executed: true })
        )
        (ok true)
    )
)

(define-public (update-node-status (node-id uint) (active bool))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get owner node-data)) ERR_UNAUTHORIZED)
        (map-set wifi-nodes
            { node-id: node-id }
            (merge node-data { active: active })
        )
        (ok true)
    )
)

(define-public (withdraw-earnings (node-id uint))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (earnings (get earnings node-data))
        )
        (asserts! (is-eq tx-sender (get owner node-data)) ERR_UNAUTHORIZED)
        (asserts! (> earnings u0) ERR_INSUFFICIENT_FUNDS)
        
        (try! (as-contract (stx-transfer? earnings tx-sender (get owner node-data))))
        (map-set wifi-nodes
            { node-id: node-id }
            (merge node-data { earnings: u0 })
        )
        (ok earnings)
    )
)

(define-read-only (get-node-info (node-id uint))
    (map-get? wifi-nodes { node-id: node-id })
)

(define-read-only (get-member-info (member principal))
    (map-get? dao-members { member: member })
)

(define-read-only (get-proposal-info (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-usage-info (node-id uint) (user principal))
    (map-get? node-usage { node-id: node-id, user: user })
)

(define-read-only (get-vote-info (proposal-id uint) (voter principal))
    (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-membership-fee)
    (var-get membership-fee)
)

(define-read-only (get-next-node-id)
    (var-get next-node-id)
)

(define-read-only (get-next-proposal-id)
    (var-get next-proposal-id)
)

(define-public (rate-wifi-node (node-id uint) (rating uint))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (usage-data (unwrap! (map-get? node-usage { node-id: node-id, user: tx-sender }) ERR_INSUFFICIENT_SESSIONS))
            (existing-rating (map-get? node-ratings { node-id: node-id, rater: tx-sender }))
            (current-sessions (get data-used usage-data))
        )
        (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
        (asserts! (is-none existing-rating) ERR_ALREADY_RATED)
        (asserts! (> current-sessions u0) ERR_INSUFFICIENT_SESSIONS)
        
        (map-set node-ratings
            { node-id: node-id, rater: tx-sender }
            {
                rating: rating,
                session-count: current-sessions,
                created-at: stacks-block-height
            }
        )
        
        (let
            (
                (new-rating-sum (+ (get rating-sum node-data) rating))
                (new-total-ratings (+ (get total-ratings node-data) u1))
                (new-avg-rating (/ new-rating-sum new-total-ratings))
                (sessions-factor (if (>= (get total-sessions node-data) u100) u10 (/ (get total-sessions node-data) u10)))
                (reliability-bonus (if (>= (get reliability-score node-data) u80) u5 u0))
                (new-quality-score (+ new-avg-rating sessions-factor reliability-bonus))
            )
            (map-set wifi-nodes
                { node-id: node-id }
                (merge node-data {
                    total-ratings: new-total-ratings,
                    rating-sum: new-rating-sum,
                    quality-score: (if (>= new-quality-score u100) u100 new-quality-score)
                })
            )
        )
        (ok true)
    )
)

(define-public (update-node-reliability (node-id uint) (successful-connection bool))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (current-reliability (get reliability-score node-data))
        )
        (asserts! (is-eq tx-sender (get owner node-data)) ERR_UNAUTHORIZED)
        
        (let
            (
                (adjustment (if successful-connection u2 (- u0 u5)))
                (new-reliability (if successful-connection
                    (if (>= (+ current-reliability adjustment) u100) u100 (+ current-reliability adjustment))
                    (if (>= current-reliability u5) (- current-reliability u5) u0)
                ))
            )
            (map-set wifi-nodes
                { node-id: node-id }
                (merge node-data { reliability-score: new-reliability })
            )
        )
        (ok true)
    )
)

(define-public (set-quality-threshold (level uint) (min-score uint) (bonus-pct uint) (visible bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= min-score u100) ERR_INVALID_AMOUNT)
        (asserts! (<= bonus-pct u50) ERR_INVALID_AMOUNT)
        
        (map-set quality-thresholds
            { threshold-level: level }
            {
                min-score: min-score,
                bonus-percentage: bonus-pct,
                max-visible: visible
            }
        )
        (ok true)
    )
)

(define-public (get-quality-adjusted-pricing (node-id uint) (base-cost uint))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (quality-score (get quality-score node-data))
            (threshold-bronze (default-to 
                { min-score: u60, bonus-percentage: u0, max-visible: true }
                (map-get? quality-thresholds { threshold-level: u1 })
            ))
            (threshold-silver (default-to 
                { min-score: u80, bonus-percentage: u10, max-visible: true }
                (map-get? quality-thresholds { threshold-level: u2 })
            ))
            (threshold-gold (default-to 
                { min-score: u95, bonus-percentage: u25, max-visible: true }
                (map-get? quality-thresholds { threshold-level: u3 })
            ))
        )
        (asserts! (>= quality-score (var-get min-quality-score)) ERR_QUALITY_TOO_LOW)
        
        (let
            (
                (bonus-pct (if (>= quality-score (get min-score threshold-gold))
                    (get bonus-percentage threshold-gold)
                    (if (>= quality-score (get min-score threshold-silver))
                        (get bonus-percentage threshold-silver)
                        (get bonus-percentage threshold-bronze)
                    )
                ))
                (bonus-amount (/ (* base-cost bonus-pct) u100))
                (final-cost (+ base-cost bonus-amount))
            )
            (ok final-cost)
        )
    )
)

(define-public (initialize-quality-system)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (try! (set-quality-threshold u1 u60 u0 true))
        (try! (set-quality-threshold u2 u80 u10 true))
        (try! (set-quality-threshold u3 u95 u25 true))
        
        (ok true)
    )
)

(define-read-only (get-node-quality-info (node-id uint))
    (match (map-get? wifi-nodes { node-id: node-id })
        node-data (ok {
            quality-score: (get quality-score node-data),
            total-sessions: (get total-sessions node-data),
            total-ratings: (get total-ratings node-data),
            avg-rating: (if (> (get total-ratings node-data) u0)
                (/ (get rating-sum node-data) (get total-ratings node-data))
                u0
            ),
            reliability-score: (get reliability-score node-data)
        })
        ERR_NOT_FOUND
    )
)

(define-read-only (get-rating-info (node-id uint) (rater principal))
    (map-get? node-ratings { node-id: node-id, rater: rater })
)

(define-read-only (get-quality-threshold-info (level uint))
    (map-get? quality-thresholds { threshold-level: level })
)

(define-read-only (is-node-quality-sufficient (node-id uint))
    (match (map-get? wifi-nodes { node-id: node-id })
        node-data (>= (get quality-score node-data) (var-get min-quality-score))
        false
    )
)

(define-public (create-coverage-zone (name (string-ascii 50)) (latitude uint) (longitude uint) (radius uint))
    (let
        (
            (zone-id (var-get next-zone-id))
            (member-data (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_MEMBER))
        )
        (asserts! (>= (get voting-power member-data) u1) ERR_UNAUTHORIZED)
        (asserts! (and (> latitude u0) (> longitude u0) (> radius u0)) ERR_INVALID_COORDINATES)
        
        (map-set coverage-zones
            { zone-id: zone-id }
            {
                name: name,
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                admin: tx-sender,
                active: true,
                node-count: u0,
                total-bandwidth: u0,
                avg-quality: u0,
                coverage-bonus: (var-get default-zone-incentive),
                created-at: stacks-block-height
            }
        )
        
        (map-set zone-coverage-stats
            { zone-id: zone-id }
            {
                peak-usage: u0,
                avg-usage: u0,
                coverage-density: u0,
                last-updated: stacks-block-height,
                incentive-multiplier: u100
            }
        )
        
        (var-set next-zone-id (+ zone-id u1))
        (ok zone-id)
    )
)

(define-public (update-zone-stats (zone-id uint))
    (let
        (
            (zone-data (unwrap! (map-get? coverage-zones { zone-id: zone-id }) ERR_ZONE_NOT_FOUND))
            (zone-nodes-list (get-zone-node-count zone-id))
            (total-quality (calculate-zone-quality zone-id))
            (total-bandwidth (calculate-zone-bandwidth zone-id))
        )
        (map-set coverage-zones
            { zone-id: zone-id }
            (merge zone-data {
                node-count: zone-nodes-list,
                total-bandwidth: total-bandwidth,
                avg-quality: (if (> zone-nodes-list u0) (/ total-quality zone-nodes-list) u0)
            })
        )
        
        (let
            (
                (coverage-ratio (if (> zone-nodes-list u0) (/ (* zone-nodes-list u100) (var-get max-nodes-per-zone)) u0))
                (new-multiplier (if (< coverage-ratio u50) u150 (if (< coverage-ratio u80) u120 u100)))
            )
            (map-set zone-coverage-stats
                { zone-id: zone-id }
                (merge (default-to 
                    { peak-usage: u0, avg-usage: u0, coverage-density: u0, last-updated: u0, incentive-multiplier: u100 }
                    (map-get? zone-coverage-stats { zone-id: zone-id })
                ) {
                    coverage-density: coverage-ratio,
                    last-updated: stacks-block-height,
                    incentive-multiplier: new-multiplier
                })
            )
        )
        (ok true)
    )
)

(define-public (assign-node-to-zone (node-id uint) (zone-id uint))
    (let
        (
            (node-data (unwrap! (map-get? wifi-nodes { node-id: node-id }) ERR_NOT_FOUND))
            (zone-data (unwrap! (map-get? coverage-zones { zone-id: zone-id }) ERR_ZONE_NOT_FOUND))
            (current-zone (get zone-id node-data))
        )
        (asserts! (is-eq tx-sender (get owner node-data)) ERR_UNAUTHORIZED)
        (asserts! (get active zone-data) ERR_ZONE_INACTIVE)
        (asserts! (< (get node-count zone-data) (var-get max-nodes-per-zone)) ERR_INVALID_AMOUNT)
        
        (if (> current-zone u0)
            (map-delete zone-nodes { zone-id: current-zone, node-id: node-id })
            true
        )
        
        (map-set wifi-nodes
            { node-id: node-id }
            (merge node-data { zone-id: zone-id })
        )
        
        (map-set zone-nodes
            { zone-id: zone-id, node-id: node-id }
            { assigned-at: stacks-block-height, contribution-score: u50 }
        )
        
        (if (> current-zone u0)
            (try! (update-zone-stats current-zone))
            true
        )
        (try! (update-zone-stats zone-id))
        (ok true)
    )
)

(define-public (set-zone-incentive (zone-id uint) (bonus-percentage uint))
    (let
        (
            (zone-data (unwrap! (map-get? coverage-zones { zone-id: zone-id }) ERR_ZONE_NOT_FOUND))
        )
        (asserts! (or (is-eq tx-sender (get admin zone-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_ZONE_ADMIN)
        (asserts! (<= bonus-percentage u100) ERR_INVALID_AMOUNT)
        
        (map-set coverage-zones
            { zone-id: zone-id }
            (merge zone-data { coverage-bonus: bonus-percentage })
        )
        (ok true)
    )
)

(define-public (toggle-zone-status (zone-id uint))
    (let
        (
            (zone-data (unwrap! (map-get? coverage-zones { zone-id: zone-id }) ERR_ZONE_NOT_FOUND))
        )
        (asserts! (or (is-eq tx-sender (get admin zone-data)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_ZONE_ADMIN)
        
        (map-set coverage-zones
            { zone-id: zone-id }
            (merge zone-data { active: (not (get active zone-data)) })
        )
        (ok true)
    )
)

(define-public (get-zone-pricing-multiplier (zone-id uint))
    (let
        (
            (zone-data (unwrap! (map-get? coverage-zones { zone-id: zone-id }) ERR_ZONE_NOT_FOUND))
            (stats-data (default-to 
                { peak-usage: u0, avg-usage: u0, coverage-density: u0, last-updated: u0, incentive-multiplier: u100 }
                (map-get? zone-coverage-stats { zone-id: zone-id })
            ))
        )
        (let
            (
                (base-bonus (get coverage-bonus zone-data))
                (density-multiplier (get incentive-multiplier stats-data))
                (final-multiplier (+ u100 base-bonus (if (> density-multiplier u100) (- density-multiplier u100) u0)))
            )
            (ok (if (> final-multiplier u200) u200 final-multiplier))
        )
    )
)

(define-private (get-zone-node-count (zone-id uint))
    (get count (fold count-zone-nodes 
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20 u21 u22 u23 u24 u25 u26 u27 u28 u29 u30 u31 u32 u33 u34 u35 u36 u37 u38 u39 u40 u41 u42 u43 u44 u45 u46 u47 u48 u49 u50)
        { zone-id: zone-id, count: u0 }
    ))
)

(define-private (count-zone-nodes (node-id uint) (accumulator { zone-id: uint, count: uint }))
    (let
        (
            (target-zone (get zone-id accumulator))
            (node-data (map-get? wifi-nodes { node-id: node-id }))
        )
        (if (and (is-some node-data) (is-eq (get zone-id (unwrap-panic node-data)) target-zone))
            { zone-id: target-zone, count: (+ (get count accumulator) u1) }
            accumulator
        )
    )
)

(define-private (calculate-zone-quality (zone-id uint))
    (get total (fold sum-zone-quality 
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20 u21 u22 u23 u24 u25 u26 u27 u28 u29 u30 u31 u32 u33 u34 u35 u36 u37 u38 u39 u40 u41 u42 u43 u44 u45 u46 u47 u48 u49 u50)
        { zone-id: zone-id, total: u0 }
    ))
)

(define-private (sum-zone-quality (node-id uint) (accumulator { zone-id: uint, total: uint }))
    (let
        (
            (target-zone (get zone-id accumulator))
            (node-data (map-get? wifi-nodes { node-id: node-id }))
        )
        (if (and (is-some node-data) (is-eq (get zone-id (unwrap-panic node-data)) target-zone))
            { zone-id: target-zone, total: (+ (get total accumulator) (get quality-score (unwrap-panic node-data))) }
            accumulator
        )
    )
)

(define-private (calculate-zone-bandwidth (zone-id uint))
    (get total (fold sum-zone-bandwidth 
        (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19 u20 u21 u22 u23 u24 u25 u26 u27 u28 u29 u30 u31 u32 u33 u34 u35 u36 u37 u38 u39 u40 u41 u42 u43 u44 u45 u46 u47 u48 u49 u50)
        { zone-id: zone-id, total: u0 }
    ))
)

(define-private (sum-zone-bandwidth (node-id uint) (accumulator { zone-id: uint, total: uint }))
    (let
        (
            (target-zone (get zone-id accumulator))
            (node-data (map-get? wifi-nodes { node-id: node-id }))
        )
        (if (and (is-some node-data) (is-eq (get zone-id (unwrap-panic node-data)) target-zone) (get active (unwrap-panic node-data)))
            { zone-id: target-zone, total: (+ (get total accumulator) (get bandwidth (unwrap-panic node-data))) }
            accumulator
        )
    )
)

(define-read-only (get-zone-info (zone-id uint))
    (map-get? coverage-zones { zone-id: zone-id })
)

(define-read-only (get-zone-stats (zone-id uint))
    (map-get? zone-coverage-stats { zone-id: zone-id })
)

(define-read-only (get-zone-node-assignment (zone-id uint) (node-id uint))
    (map-get? zone-nodes { zone-id: zone-id, node-id: node-id })
)

(define-read-only (get-next-zone-id)
    (var-get next-zone-id)
)


