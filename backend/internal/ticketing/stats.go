package ticketing

// StatsRow represents stats row.
type StatsRow struct {
	OrderID    string
	EventID    int64
	EventTitle string
	Status     string
	TotalCents int64
	ItemType   string
	ProductRef string
	Quantity   int64
}

// StatsBucket represents stats bucket.
type StatsBucket struct {
	EventID                 int64
	EventTitle              string
	PurchasedAmountCents    int64
	RedeemedAmountCents     int64
	TicketTypeCounts        map[string]int64
	TransferDirectionCounts map[string]int64
}

// NewStatsBucket creates stats bucket.
func NewStatsBucket(eventID int64, title string) StatsBucket {
	return StatsBucket{
		EventID:                 eventID,
		EventTitle:              title,
		TicketTypeCounts:        map[string]int64{"SINGLE": 0, "GROUP2": 0, "GROUP10": 0},
		TransferDirectionCounts: map[string]int64{"THERE": 0, "BACK": 0, "ROUNDTRIP": 0},
	}
}

// AggregateStats handles aggregate stats.
func AggregateStats(rows []StatsRow) (StatsBucket, map[int64]StatsBucket) {
	global := NewStatsBucket(0, "")
	perEvent := map[int64]StatsBucket{}
	seenOrder := map[string]struct{}{}
	for _, row := range rows {
		if row.EventID <= 0 {
			continue
		}
		bucket, ok := perEvent[row.EventID]
		if !ok {
			bucket = NewStatsBucket(row.EventID, row.EventTitle)
		}
		if bucket.EventTitle == "" && row.EventTitle != "" {
			bucket.EventTitle = row.EventTitle
		}

		// Total values should be counted once per order+status pair.
		orderKey := orderKey(row)
		if _, exists := seenOrder[orderKey]; !exists {
			if isPurchasedStatus(row.Status) {
				bucket.PurchasedAmountCents += row.TotalCents
				global.PurchasedAmountCents += row.TotalCents
			}
			if row.Status == "REDEEMED" {
				bucket.RedeemedAmountCents += row.TotalCents
				global.RedeemedAmountCents += row.TotalCents
			}
			seenOrder[orderKey] = struct{}{}
		}

		if isPurchasedStatus(row.Status) {
			switch row.ItemType {
			case "TICKET":
				if _, ok := bucket.TicketTypeCounts[row.ProductRef]; ok {
					bucket.TicketTypeCounts[row.ProductRef] += row.Quantity
					global.TicketTypeCounts[row.ProductRef] += row.Quantity
				}
			case "TRANSFER":
				if _, ok := bucket.TransferDirectionCounts[row.ProductRef]; ok {
					bucket.TransferDirectionCounts[row.ProductRef] += row.Quantity
					global.TransferDirectionCounts[row.ProductRef] += row.Quantity
				}
			}
		}

		perEvent[row.EventID] = bucket
	}
	return global, perEvent
}

// orderKey handles order key.
func orderKey(row StatsRow) string {
	return row.OrderID + "|" + row.Status
}

// isPurchasedStatus reports whether purchased status condition is met.
func isPurchasedStatus(status string) bool {
	switch status {
	case "PAID", "CONFIRMED", "REDEEMED":
		return true
	default:
		return false
	}
}
