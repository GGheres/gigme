package models

import "time"

type User struct {
	ID         int64     `json:"id"`
	TelegramID int64     `json:"telegramId"`
	Username   string    `json:"username,omitempty"`
	FirstName  string    `json:"firstName"`
	LastName   string    `json:"lastName,omitempty"`
	PhotoURL   string    `json:"photoUrl,omitempty"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

type Event struct {
	ID                 int64      `json:"id"`
	CreatorUserID      int64      `json:"creatorUserId"`
	Title              string     `json:"title"`
	Description        string     `json:"description"`
	StartsAt           time.Time  `json:"startsAt"`
	EndsAt             *time.Time `json:"endsAt,omitempty"`
	Lat                float64    `json:"lat"`
	Lng                float64    `json:"lng"`
	AddressLabel       string     `json:"addressLabel,omitempty"`
	ContactTelegram    string     `json:"contactTelegram,omitempty"`
	ContactWhatsapp    string     `json:"contactWhatsapp,omitempty"`
	ContactWechat      string     `json:"contactWechat,omitempty"`
	ContactFbMessenger string     `json:"contactFbMessenger,omitempty"`
	ContactSnapchat    string     `json:"contactSnapchat,omitempty"`
	Capacity           *int       `json:"capacity,omitempty"`
	IsHidden           bool       `json:"isHidden"`
	PromotedUntil      *time.Time `json:"promotedUntil,omitempty"`
	Participants       int        `json:"participantsCount"`
	CreatorName        string     `json:"creatorName,omitempty"`
	ThumbnailURL       string     `json:"thumbnailUrl,omitempty"`
	Filters            []string   `json:"filters,omitempty"`
	IsJoined           bool       `json:"isJoined,omitempty"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
}

type EventMarker struct {
	ID         int64     `json:"id"`
	Title      string    `json:"title"`
	StartsAt   time.Time `json:"startsAt"`
	Lat        float64   `json:"lat"`
	Lng        float64   `json:"lng"`
	IsPromoted bool      `json:"isPromoted"`
	Filters    []string  `json:"filters,omitempty"`
}

type Participant struct {
	UserID   int64     `json:"userId"`
	Name     string    `json:"name"`
	JoinedAt time.Time `json:"joinedAt"`
}

type NotificationJob struct {
	ID        int64                  `json:"id"`
	UserID    int64                  `json:"userId"`
	Kind      string                 `json:"kind"`
	EventID   *int64                 `json:"eventId,omitempty"`
	RunAt     time.Time              `json:"runAt"`
	Payload   map[string]interface{} `json:"payload"`
	Status    string                 `json:"status"`
	Attempts  int                    `json:"attempts"`
	LastError string                 `json:"lastError,omitempty"`
}
