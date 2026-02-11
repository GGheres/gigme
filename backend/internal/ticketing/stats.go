package ticketing

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

type StatsBucket struct {
	EventID                 int64
	EventTitle              string
	PurchasedAmountCents    int64
	RedeemedAmountCents     int64
	TicketTypeCounts        map[string]int64
	TransferDirectionCounts map[string]int64
}

func NewStatsBucket(eventID int64, title string) StatsBucket {
	return StatsBucket{
		EventID:                 eventID,
		EventTitle:              title,
		TicketTypeCounts:        map[string]int64{"SINGLE": 0, "GROUP2": 0, "GROUP10": 0},
		TransferDirectionCounts: map[string]int64{"THERE": 0, "BACK": 0, "ROUNDTRIP": 0},
	}
}

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

func orderKey(row StatsRow) string {
	return row.OrderID + "|" + row.Status
}

func isPurchasedStatus(status string) bool {
	switch status {
	case "PAID", "CONFIRMED", "REDEEMED":
		return true
	default:
		return false
	}
}
