package models

import "time"

// User represents user.
type User struct {
	ID            int64     `json:"id"`
	TelegramID    int64     `json:"telegramId"`
	Username      string    `json:"username,omitempty"`
	FirstName     string    `json:"firstName"`
	LastName      string    `json:"lastName,omitempty"`
	PhotoURL      string    `json:"photoUrl,omitempty"`
	Rating        float64   `json:"rating"`
	RatingCount   int       `json:"ratingCount"`
	BalanceTokens int64     `json:"balanceTokens"`
	CreatedAt     time.Time `json:"createdAt"`
	UpdatedAt     time.Time `json:"updatedAt"`
}

// UserPushToken represents user push token.
type UserPushToken struct {
	UserID     int64     `json:"userId"`
	Platform   string    `json:"platform"`
	Token      string    `json:"token"`
	DeviceID   string    `json:"deviceId,omitempty"`
	AppVersion string    `json:"appVersion,omitempty"`
	Locale     string    `json:"locale,omitempty"`
	IsActive   bool      `json:"isActive"`
	LastSeenAt time.Time `json:"lastSeenAt"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

// Event represents event.
type Event struct {
	ID                 int64      `json:"id"`
	CreatorUserID      int64      `json:"creatorUserId"`
	Title              string     `json:"title"`
	Description        string     `json:"description"`
	Links              []string   `json:"links,omitempty"`
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
	IsPrivate          bool       `json:"isPrivate"`
	IsLandingPublished bool       `json:"isLandingPublished"`
	PromotedUntil      *time.Time `json:"promotedUntil,omitempty"`
	AccessKey          string     `json:"accessKey,omitempty"`
	Participants       int        `json:"participantsCount"`
	CreatorName        string     `json:"creatorName,omitempty"`
	ThumbnailURL       string     `json:"thumbnailUrl,omitempty"`
	Filters            []string   `json:"filters,omitempty"`
	IsJoined           bool       `json:"isJoined,omitempty"`
	LikesCount         int        `json:"likesCount"`
	CommentsCount      int        `json:"commentsCount"`
	IsLiked            bool       `json:"isLiked,omitempty"`
	CreatedAt          time.Time  `json:"createdAt"`
	UpdatedAt          time.Time  `json:"updatedAt"`
}

// UserEvent represents user event.
type UserEvent struct {
	ID                int64     `json:"id"`
	Title             string    `json:"title"`
	StartsAt          time.Time `json:"startsAt"`
	ParticipantsCount int       `json:"participantsCount"`
	ThumbnailURL      string    `json:"thumbnailUrl,omitempty"`
}

// LandingContent represents landing content.
type LandingContent struct {
	HeroEyebrow         string    `json:"heroEyebrow"`
	HeroTitle           string    `json:"heroTitle"`
	HeroDescription     string    `json:"heroDescription"`
	HeroPrimaryCTALabel string    `json:"heroPrimaryCtaLabel"`
	AboutTitle          string    `json:"aboutTitle"`
	AboutDescription    string    `json:"aboutDescription"`
	PartnersTitle       string    `json:"partnersTitle"`
	PartnersDescription string    `json:"partnersDescription"`
	FooterText          string    `json:"footerText"`
	UpdatedBy           *int64    `json:"updatedBy,omitempty"`
	CreatedAt           time.Time `json:"createdAt"`
	UpdatedAt           time.Time `json:"updatedAt"`
}

// EventMarker represents event marker.
type EventMarker struct {
	ID         int64     `json:"id"`
	Title      string    `json:"title"`
	StartsAt   time.Time `json:"startsAt"`
	Lat        float64   `json:"lat"`
	Lng        float64   `json:"lng"`
	IsPromoted bool      `json:"isPromoted"`
	Filters    []string  `json:"filters,omitempty"`
}

// Participant represents participant.
type Participant struct {
	UserID   int64     `json:"userId"`
	Name     string    `json:"name"`
	JoinedAt time.Time `json:"joinedAt"`
}

// NotificationJob represents notification job.
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

// EventComment represents event comment.
type EventComment struct {
	ID        int64     `json:"id"`
	EventID   int64     `json:"eventId"`
	UserID    int64     `json:"userId"`
	UserName  string    `json:"userName"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"createdAt"`
}

// AdminUser represents admin user.
type AdminUser struct {
	ID            int64      `json:"id"`
	TelegramID    int64      `json:"telegramId"`
	Username      string     `json:"username,omitempty"`
	FirstName     string     `json:"firstName"`
	LastName      string     `json:"lastName,omitempty"`
	PhotoURL      string     `json:"photoUrl,omitempty"`
	Rating        float64    `json:"rating"`
	RatingCount   int        `json:"ratingCount"`
	BalanceTokens int64      `json:"balanceTokens"`
	IsBlocked     bool       `json:"isBlocked"`
	BlockedReason string     `json:"blockedReason,omitempty"`
	BlockedAt     *time.Time `json:"blockedAt,omitempty"`
	LastSeenAt    *time.Time `json:"lastSeenAt,omitempty"`
	CreatedAt     time.Time  `json:"createdAt"`
	UpdatedAt     time.Time  `json:"updatedAt"`
}

// AdminBroadcast represents admin broadcast.
type AdminBroadcast struct {
	ID          int64                  `json:"id"`
	AdminUserID int64                  `json:"adminUserId"`
	Audience    string                 `json:"audience"`
	Payload     map[string]interface{} `json:"payload"`
	Status      string                 `json:"status"`
	CreatedAt   time.Time              `json:"createdAt"`
	UpdatedAt   time.Time              `json:"updatedAt"`
	Targeted    int                    `json:"targeted"`
	Sent        int                    `json:"sent"`
	Failed      int                    `json:"failed"`
}

// AdminBroadcastJob represents admin broadcast job.
type AdminBroadcastJob struct {
	ID           int64  `json:"id"`
	BroadcastID  int64  `json:"broadcastId"`
	TargetUserID int64  `json:"targetUserId"`
	Status       string `json:"status"`
	Attempts     int    `json:"attempts"`
	LastError    string `json:"lastError,omitempty"`
}

// AdminBotMessage represents admin bot message.
type AdminBotMessage struct {
	ID                int64     `json:"id"`
	ChatID            int64     `json:"chatId"`
	Direction         string    `json:"direction"`
	Text              string    `json:"text"`
	TelegramMessageID *int64    `json:"telegramMessageId,omitempty"`
	SenderTelegramID  *int64    `json:"senderTelegramId,omitempty"`
	SenderUsername    string    `json:"senderUsername,omitempty"`
	SenderFirstName   string    `json:"senderFirstName,omitempty"`
	SenderLastName    string    `json:"senderLastName,omitempty"`
	AdminTelegramID   *int64    `json:"adminTelegramId,omitempty"`
	UserID            *int64    `json:"userId,omitempty"`
	UserUsername      string    `json:"userUsername,omitempty"`
	UserFirstName     string    `json:"userFirstName,omitempty"`
	UserLastName      string    `json:"userLastName,omitempty"`
	CreatedAt         time.Time `json:"createdAt"`
}

// AdminParserSource represents admin parser source.
type AdminParserSource struct {
	ID           int64      `json:"id"`
	SourceType   string     `json:"sourceType"`
	Input        string     `json:"input"`
	Title        string     `json:"title,omitempty"`
	IsActive     bool       `json:"isActive"`
	LastParsedAt *time.Time `json:"lastParsedAt,omitempty"`
	CreatedBy    int64      `json:"createdBy"`
	CreatedAt    time.Time  `json:"createdAt"`
	UpdatedAt    time.Time  `json:"updatedAt"`
}

// AdminParsedEvent represents admin parsed event.
type AdminParsedEvent struct {
	ID              int64      `json:"id"`
	SourceID        *int64     `json:"sourceId,omitempty"`
	SourceType      string     `json:"sourceType"`
	Input           string     `json:"input"`
	Name            string     `json:"name"`
	DateTime        *time.Time `json:"dateTime,omitempty"`
	Location        string     `json:"location"`
	Description     string     `json:"description"`
	Links           []string   `json:"links"`
	Status          string     `json:"status"`
	ParserError     string     `json:"parserError,omitempty"`
	ParsedAt        time.Time  `json:"parsedAt"`
	ImportedEventID *int64     `json:"importedEventId,omitempty"`
	ImportedBy      *int64     `json:"importedBy,omitempty"`
	ImportedAt      *time.Time `json:"importedAt,omitempty"`
	CreatedAt       time.Time  `json:"createdAt"`
	UpdatedAt       time.Time  `json:"updatedAt"`
}
