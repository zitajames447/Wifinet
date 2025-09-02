;; Wi-Fi Network Analytics Dashboard
;; Simple analytics and insights for Wifinet ecosystem

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NO_DATA (err u201))
(define-constant ERR_NODE_NOT_FOUND (err u202))
(define-constant ERR_NOT_NODE_OWNER (err u203))

;; Network-wide statistics
(define-data-var total-network-earnings uint u0)
(define-data-var total-network-data uint u0)
(define-data-var total-active-nodes uint u0)

;; Node analytics data
(define-map node-analytics
    { node-id: uint }
    {
        total-earnings: uint,
        total-data-served: uint,
        session-count: uint,
        avg-rating: uint,
        last-updated: uint
    }
)

;; Zone analytics data
(define-map zone-analytics
    { zone-id: uint }
    {
        total-nodes: uint,
        total-earnings: uint,
        total-bandwidth: uint,
        avg-quality: uint,
        last-updated: uint
    }
)

;; Daily performance snapshots
(define-map daily-stats
    { date: uint }
    {
        total-earnings: uint,
        total-data: uint,
        active-nodes: uint,
        avg-network-quality: uint
    }
)

;; Update node analytics - called by node owner or authorized contracts
(define-public (update-node-analytics (node-id uint) (earnings uint) (data-served uint) (sessions uint))
    (let
        (
            (current-stats (default-to 
                { total-earnings: u0, total-data-served: u0, session-count: u0, avg-rating: u0, last-updated: u0 }
                (map-get? node-analytics { node-id: node-id })
            ))
        )
        ;; For simplicity, allow any caller - in production would check node ownership
        (map-set node-analytics
            { node-id: node-id }
            {
                total-earnings: (+ (get total-earnings current-stats) earnings),
                total-data-served: (+ (get total-data-served current-stats) data-served),
                session-count: (+ (get session-count current-stats) sessions),
                avg-rating: (get avg-rating current-stats),
                last-updated: stacks-block-height
            }
        )
        
        ;; Update network totals
        (var-set total-network-earnings (+ (var-get total-network-earnings) earnings))
        (var-set total-network-data (+ (var-get total-network-data) data-served))
        
        (ok true)
    )
)

;; Update zone analytics
(define-public (update-zone-analytics (zone-id uint) (node-count uint) (total-earnings uint) (total-bandwidth uint) (avg-quality uint))
    (begin
        (map-set zone-analytics
            { zone-id: zone-id }
            {
                total-nodes: node-count,
                total-earnings: total-earnings,
                total-bandwidth: total-bandwidth,
                avg-quality: avg-quality,
                last-updated: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Record daily network snapshot
(define-public (record-daily-snapshot (date uint) (earnings uint) (data uint) (active-nodes uint) (avg-quality uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set daily-stats
            { date: date }
            {
                total-earnings: earnings,
                total-data: data,
                active-nodes: active-nodes,
                avg-network-quality: avg-quality
            }
        )
        (ok true)
    )
)

;; Get network summary
(define-read-only (get-network-summary)
    (ok {
        total-earnings: (var-get total-network-earnings),
        total-data: (var-get total-network-data),
        active-nodes: (var-get total-active-nodes)
    })
)

;; Get node analytics
(define-read-only (get-node-analytics (node-id uint))
    (match (map-get? node-analytics { node-id: node-id })
        stats (ok stats)
        (err ERR_NO_DATA)
    )
)

;; Get zone analytics
(define-read-only (get-zone-analytics (zone-id uint))
    (match (map-get? zone-analytics { zone-id: zone-id })
        stats (ok stats)
        (err ERR_NO_DATA)
    )
)

;; Get daily stats
(define-read-only (get-daily-stats (date uint))
    (match (map-get? daily-stats { date: date })
        stats (ok stats)
        (err ERR_NO_DATA)
    )
)

;; Calculate node efficiency (earnings per data unit)
(define-read-only (get-node-efficiency (node-id uint))
    (match (map-get? node-analytics { node-id: node-id })
        stats 
            (if (> (get total-data-served stats) u0)
                (ok (/ (get total-earnings stats) (get total-data-served stats)))
                (ok u0)
            )
        (err ERR_NO_DATA)
    )
)

;; Get top performing nodes (simplified - returns first 5 nodes with data)
(define-read-only (get-top-nodes)
    (let
        (
            (node1 (map-get? node-analytics { node-id: u1 }))
            (node2 (map-get? node-analytics { node-id: u2 }))
            (node3 (map-get? node-analytics { node-id: u3 }))
            (node4 (map-get? node-analytics { node-id: u4 }))
            (node5 (map-get? node-analytics { node-id: u5 }))
        )
        (ok {
            node1: node1,
            node2: node2,
            node3: node3,
            node4: node4,
            node5: node5
        })
    )
)

;; Update active node count
(define-public (set-active-node-count (count uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set total-active-nodes count)
        (ok true)
    )
)

;; Get network growth metrics
(define-read-only (get-network-growth (start-date uint) (end-date uint))
    (let
        (
            (start-stats (map-get? daily-stats { date: start-date }))
            (end-stats (map-get? daily-stats { date: end-date }))
        )
        (if (and (is-some start-stats) (is-some end-stats))
            (let
                (
                    (start-data (unwrap-panic start-stats))
                    (end-data (unwrap-panic end-stats))
                    (earnings-growth (- (get total-earnings end-data) (get total-earnings start-data)))
                    (nodes-growth (- (get active-nodes end-data) (get active-nodes start-data)))
                )
                (ok {
                    earnings-growth: earnings-growth,
                    nodes-growth: nodes-growth,
                    data-growth: (- (get total-data end-data) (get total-data start-data))
                })
            )
            (err ERR_NO_DATA)
        )
    )
)

;; Simple analytics for zone comparison
(define-read-only (compare-zones (zone1 uint) (zone2 uint))
    (let
        (
            (zone1-stats (map-get? zone-analytics { zone-id: zone1 }))
            (zone2-stats (map-get? zone-analytics { zone-id: zone2 }))
        )
        (if (and (is-some zone1-stats) (is-some zone2-stats))
            (let
                (
                    (z1 (unwrap-panic zone1-stats))
                    (z2 (unwrap-panic zone2-stats))
                )
                (ok {
                    zone1-performance: (if (> (get total-nodes z1) u0) (/ (get total-earnings z1) (get total-nodes z1)) u0),
                    zone2-performance: (if (> (get total-nodes z2) u0) (/ (get total-earnings z2) (get total-nodes z2)) u0),
                    better-zone: (if (> (get total-earnings z1) (get total-earnings z2)) zone1 zone2)
                })
            )
            (err ERR_NO_DATA)
        )
    )
)
