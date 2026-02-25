package models

import "time"

const (
	OrderStatusPending   = "PENDING"
	OrderStatusPaid      = "PAID"
	OrderStatusConfirmed = OrderStatusPaid // Backward-compatible alias.
	OrderStatusCanceled  = "CANCELED"
	OrderStatusRedeemed  = "REDEEMED"
)

const (
	ItemTypeTicket   = "TICKET"
	ItemTypeTransfer = "TRANSFER"
)

const (
	TicketTypeSingle  = "SINGLE"
	TicketTypeGroup2  = "GROUP2"
	TicketTypeGroup10 = "GROUP10"
)

const (
	TransferDirectionThere     = "THERE"
	TransferDirectionBack      = "BACK"
	TransferDirectionRoundTrip = "ROUNDTRIP"
)

const (
	DiscountTypePercent = "PERCENT"
	DiscountTypeFixed   = "FIXED"
)

const (
	PaymentMethodPhone       = "PHONE"
	PaymentMethodUSDT        = "USDT"
	PaymentMethodQR          = "PAYMENT_QR"
	PaymentMethodTochkaSBPQR = "TOCHKA_SBP_QR"
)

var TicketGroupSizeByType = map[string]int{
	TicketTypeSingle:  1,
	TicketTypeGroup2:  2,
	TicketTypeGroup10: 10,
}

// TicketProduct represents ticket product.
type TicketProduct struct {
	ID             string    `json:"id"`
	EventID        int64     `json:"eventId"`
	Name           string    `json:"name,omitempty"`
	Type           string    `json:"type"`
	PriceCents     int64     `json:"priceCents"`
	InventoryLimit *int      `json:"inventoryLimit,omitempty"`
	SoldCount      int       `json:"soldCount"`
	IsActive       bool      `json:"isActive"`
	CreatedBy      *int64    `json:"createdBy,omitempty"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

// TransferProduct represents transfer product.
type TransferProduct struct {
	ID             string                 `json:"id"`
	EventID        int64                  `json:"eventId"`
	Name           string                 `json:"name,omitempty"`
	Direction      string                 `json:"direction"`
	PriceCents     int64                  `json:"priceCents"`
	Info           map[string]interface{} `json:"info"`
	InventoryLimit *int                   `json:"inventoryLimit,omitempty"`
	SoldCount      int                    `json:"soldCount"`
	IsActive       bool                   `json:"isActive"`
	CreatedBy      *int64                 `json:"createdBy,omitempty"`
	CreatedAt      time.Time              `json:"createdAt"`
	UpdatedAt      time.Time              `json:"updatedAt"`
}

// PromoCode represents promo code.
type PromoCode struct {
	ID           string     `json:"id"`
	Code         string     `json:"code"`
	DiscountType string     `json:"discountType"`
	Value        int64      `json:"value"`
	UsageLimit   *int       `json:"usageLimit,omitempty"`
	UsedCount    int        `json:"usedCount"`
	ActiveFrom   *time.Time `json:"activeFrom,omitempty"`
	ActiveTo     *time.Time `json:"activeTo,omitempty"`
	EventID      *int64     `json:"eventId,omitempty"`
	IsActive     bool       `json:"isActive"`
	CreatedBy    *int64     `json:"createdBy,omitempty"`
	CreatedAt    time.Time  `json:"createdAt"`
	UpdatedAt    time.Time  `json:"updatedAt"`
}

// Order represents order.
type Order struct {
	ID               string     `json:"id"`
	UserID           int64      `json:"userId"`
	EventID          int64      `json:"eventId"`
	EventTitle       string     `json:"eventTitle,omitempty"`
	Status           string     `json:"status"`
	PaymentMethod    string     `json:"paymentMethod"`
	PaymentReference string     `json:"paymentReference,omitempty"`
	PaymentNotes     string     `json:"paymentNotes,omitempty"`
	PromoCodeID      *string    `json:"promoCodeId,omitempty"`
	SubtotalCents    int64      `json:"subtotalCents"`
	DiscountCents    int64      `json:"discountCents"`
	TotalCents       int64      `json:"totalCents"`
	Currency         string     `json:"currency"`
	ConfirmedAt      *time.Time `json:"confirmedAt,omitempty"`
	CanceledAt       *time.Time `json:"canceledAt,omitempty"`
	RedeemedAt       *time.Time `json:"redeemedAt,omitempty"`
	ConfirmedBy      *int64     `json:"confirmedBy,omitempty"`
	CanceledBy       *int64     `json:"canceledBy,omitempty"`
	CanceledReason   string     `json:"canceledReason,omitempty"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`
}

// OrderItem represents order item.
type OrderItem struct {
	ID             int64                  `json:"id"`
	OrderID        string                 `json:"orderId"`
	ItemType       string                 `json:"itemType"`
	ProductID      string                 `json:"productId"`
	ProductRef     string                 `json:"productRef"`
	Quantity       int                    `json:"quantity"`
	UnitPriceCents int64                  `json:"unitPriceCents"`
	LineTotalCents int64                  `json:"lineTotalCents"`
	Meta           map[string]interface{} `json:"meta"`
	CreatedAt      time.Time              `json:"createdAt"`
}

// Ticket represents ticket.
type Ticket struct {
	ID            string     `json:"id"`
	OrderID       string     `json:"orderId"`
	OrderStatus   string     `json:"orderStatus,omitempty"`
	UserID        int64      `json:"userId"`
	EventID       int64      `json:"eventId"`
	TicketType    string     `json:"ticketType"`
	Quantity      int        `json:"quantity"`
	QRPayload     string     `json:"qrPayload,omitempty"`
	QRPayloadHash string     `json:"qrPayloadHash,omitempty"`
	QRIssuedAt    *time.Time `json:"qrIssuedAt,omitempty"`
	RedeemedAt    *time.Time `json:"redeemedAt,omitempty"`
	RedeemedBy    *int64     `json:"redeemedBy,omitempty"`
	CreatedAt     time.Time  `json:"createdAt"`
}

// OrderUserSummary represents order user summary.
type OrderUserSummary struct {
	ID         int64  `json:"id"`
	TelegramID int64  `json:"telegramId"`
	FirstName  string `json:"firstName"`
	LastName   string `json:"lastName"`
	Username   string `json:"username"`
}

// PaymentInstructions represents payment instructions.
type PaymentInstructions struct {
	PhoneNumber    string `json:"phoneNumber,omitempty"`
	USDTWallet     string `json:"usdtWallet,omitempty"`
	USDTNetwork    string `json:"usdtNetwork,omitempty"`
	USDTMemo       string `json:"usdtMemo,omitempty"`
	PaymentQRData  string `json:"paymentQrData,omitempty"`
	PaymentQRCID   string `json:"paymentQrCId,omitempty"`
	AmountCents    int64  `json:"amountCents"`
	Currency       string `json:"currency"`
	DisplayMessage string `json:"displayMessage"`
}

// PaymentSettings represents payment settings.
type PaymentSettings struct {
	PhoneNumber      string     `json:"phoneNumber"`
	USDTWallet       string     `json:"usdtWallet"`
	USDTNetwork      string     `json:"usdtNetwork"`
	USDTMemo         string     `json:"usdtMemo"`
	PaymentQRData    string     `json:"paymentQrData"`
	PhoneEnabled     bool       `json:"phoneEnabled"`
	USDTEnabled      bool       `json:"usdtEnabled"`
	PaymentQREnabled bool       `json:"paymentQrEnabled"`
	SBPEnabled       bool       `json:"sbpEnabled"`
	PhoneDescription string     `json:"phoneDescription"`
	USDTDescription  string     `json:"usdtDescription"`
	QRDescription    string     `json:"qrDescription"`
	SBPDescription   string     `json:"sbpDescription"`
	UpdatedBy        *int64     `json:"updatedBy,omitempty"`
	CreatedAt        *time.Time `json:"createdAt,omitempty"`
	UpdatedAt        *time.Time `json:"updatedAt,omitempty"`
}

// PaymentSettingsPatch represents payment settings patch.
type PaymentSettingsPatch struct {
	PhoneNumber      *string `json:"phoneNumber,omitempty"`
	USDTWallet       *string `json:"usdtWallet,omitempty"`
	USDTNetwork      *string `json:"usdtNetwork,omitempty"`
	USDTMemo         *string `json:"usdtMemo,omitempty"`
	PaymentQRData    *string `json:"paymentQrData,omitempty"`
	PhoneEnabled     *bool   `json:"phoneEnabled,omitempty"`
	USDTEnabled      *bool   `json:"usdtEnabled,omitempty"`
	PaymentQREnabled *bool   `json:"paymentQrEnabled,omitempty"`
	SBPEnabled       *bool   `json:"sbpEnabled,omitempty"`
	PhoneDescription *string `json:"phoneDescription,omitempty"`
	USDTDescription  *string `json:"usdtDescription,omitempty"`
	QRDescription    *string `json:"qrDescription,omitempty"`
	SBPDescription   *string `json:"sbpDescription,omitempty"`
}

// SbpQR represents sbp q r.
type SbpQR struct {
	ID         string    `json:"id"`
	OrderID    string    `json:"orderId"`
	QRCID      string    `json:"qrcId"`
	Payload    string    `json:"payload"`
	MerchantID string    `json:"merchantId"`
	AccountID  string    `json:"accountId"`
	Status     string    `json:"status"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

// Payment represents payment.
type Payment struct {
	ID                string                 `json:"id"`
	OrderID           string                 `json:"orderId"`
	Provider          string                 `json:"provider"`
	ProviderPaymentID string                 `json:"providerPaymentId,omitempty"`
	Amount            int64                  `json:"amount"`
	Status            string                 `json:"status"`
	RawResponseJSON   map[string]interface{} `json:"rawResponseJson,omitempty"`
	CreatedAt         time.Time              `json:"createdAt"`
	UpdatedAt         time.Time              `json:"updatedAt"`
}

// OrderDetail represents order detail.
type OrderDetail struct {
	Order               Order               `json:"order"`
	User                *OrderUserSummary   `json:"user,omitempty"`
	Items               []OrderItem         `json:"items"`
	Tickets             []Ticket            `json:"tickets"`
	PaymentInstructions PaymentInstructions `json:"paymentInstructions"`
}

// OrderSummary represents order summary.
type OrderSummary struct {
	Order
	User *OrderUserSummary `json:"user,omitempty"`
}

// OrderProductSelection represents order product selection.
type OrderProductSelection struct {
	ProductID string `json:"productId"`
	Quantity  int    `json:"quantity"`
}

// CreateOrderParams represents create order params.
type CreateOrderParams struct {
	UserID           int64
	EventID          int64
	PaymentMethod    string
	PaymentReference string
	TicketItems      []OrderProductSelection
	TransferItems    []OrderProductSelection
	PromoCode        string
}

// PromoValidation represents promo validation.
type PromoValidation struct {
	Valid         bool   `json:"valid"`
	Code          string `json:"code"`
	DiscountType  string `json:"discountType,omitempty"`
	Value         int64  `json:"value"`
	DiscountCents int64  `json:"discountCents"`
	TotalCents    int64  `json:"totalCents"`
	Reason        string `json:"reason,omitempty"`
}

// TicketProductInput represents ticket product input.
type TicketProductInput struct {
	EventID        int64  `json:"eventId"`
	Name           string `json:"name"`
	Type           string `json:"type"`
	PriceCents     int64  `json:"priceCents"`
	InventoryLimit *int   `json:"inventoryLimit,omitempty"`
	IsActive       bool   `json:"isActive"`
}

// TicketProductPatch represents ticket product patch.
type TicketProductPatch struct {
	PriceCents     *int64 `json:"priceCents,omitempty"`
	InventoryLimit *int   `json:"inventoryLimit,omitempty"`
	IsActive       *bool  `json:"isActive,omitempty"`
}

// TransferProductInput represents transfer product input.
type TransferProductInput struct {
	EventID        int64                  `json:"eventId"`
	Name           string                 `json:"name"`
	Direction      string                 `json:"direction"`
	PriceCents     int64                  `json:"priceCents"`
	Info           map[string]interface{} `json:"info"`
	InventoryLimit *int                   `json:"inventoryLimit,omitempty"`
	IsActive       bool                   `json:"isActive"`
}

// TransferProductPatch represents transfer product patch.
type TransferProductPatch struct {
	PriceCents     *int64                 `json:"priceCents,omitempty"`
	Info           map[string]interface{} `json:"info,omitempty"`
	InventoryLimit *int                   `json:"inventoryLimit,omitempty"`
	IsActive       *bool                  `json:"isActive,omitempty"`
}

// PromoCodeInput represents promo code input.
type PromoCodeInput struct {
	Code         string     `json:"code"`
	DiscountType string     `json:"discountType"`
	Value        int64      `json:"value"`
	UsageLimit   *int       `json:"usageLimit,omitempty"`
	ActiveFrom   *time.Time `json:"activeFrom,omitempty"`
	ActiveTo     *time.Time `json:"activeTo,omitempty"`
	EventID      *int64     `json:"eventId,omitempty"`
	IsActive     bool       `json:"isActive"`
}

// PromoCodePatch represents promo code patch.
type PromoCodePatch struct {
	DiscountType *string    `json:"discountType,omitempty"`
	Value        *int64     `json:"value,omitempty"`
	UsageLimit   *int       `json:"usageLimit,omitempty"`
	ActiveFrom   *time.Time `json:"activeFrom,omitempty"`
	ActiveTo     *time.Time `json:"activeTo,omitempty"`
	EventID      *int64     `json:"eventId,omitempty"`
	IsActive     *bool      `json:"isActive,omitempty"`
}

// TicketRedeemResult represents ticket redeem result.
type TicketRedeemResult struct {
	Ticket      Ticket `json:"ticket"`
	OrderStatus string `json:"orderStatus"`
}

// TicketStatsBreakdown represents ticket stats breakdown.
type TicketStatsBreakdown struct {
	EventID                 *int64           `json:"eventId,omitempty"`
	EventTitle              string           `json:"eventTitle,omitempty"`
	PurchasedAmountCents    int64            `json:"purchasedAmountCents"`
	RedeemedAmountCents     int64            `json:"redeemedAmountCents"`
	CheckedInTickets        int64            `json:"checkedInTickets"`
	CheckedInPeople         int64            `json:"checkedInPeople"`
	TicketTypeCounts        map[string]int64 `json:"ticketTypeCounts"`
	TransferDirectionCounts map[string]int64 `json:"transferDirectionCounts"`
}

// TicketStats represents ticket stats.
type TicketStats struct {
	Global TicketStatsBreakdown   `json:"global"`
	Events []TicketStatsBreakdown `json:"events"`
}
