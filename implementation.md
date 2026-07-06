# Implementation Plan: ISKRY Transfer Landing for Space App

## 0. Context

Project: existing Flutter / Flutter Web application `Space App`.

Goal: add a separate landing page for ISKRY transfer registration and payment:

```text
https://spacefestival.fun/iskry
```

The ISKRY landing must use the existing Space App infrastructure:

- existing database;
- existing product system;
- existing order system;
- existing payment flow;
- existing QR-code generation;
- existing Telegram QR delivery;
- existing Space App admin panel.

Do not build a separate payment system, separate database, separate QR system, or separate Telegram delivery mechanism.

---

## 1. Main Business Requirements

The `/iskry` page allows a user to:

1. Select a transfer product.
2. Select the number of seats.
3. Enter a Telegram contact where the QR code will be sent.
4. Optionally enter name and phone number.
5. Click `Оплатить`.
6. Complete payment using the existing payment flow.
7. Receive one QR code in Telegram after successful payment.

Important business rules:

- ISKRY currently sells only transfer products.
- One paid order must generate one QR code.
- One QR code can represent multiple seats.
- One bus has 53 seats.
- Seat overselling must be prevented.
- ISKRY transfer products must appear only on `/iskry`.
- ISKRY transfer products must not appear on the main SPACE landing or unrelated product listings.

---

## 2. First Step: Inspect Existing Architecture

Before writing code, inspect the current project structure and identify:

1. Current `Product` model.
2. Current `Order` model.
3. Current payment service / payment flow.
4. Current payment callback / webhook handling.
5. Current QR-code generation flow.
6. Current Telegram QR delivery flow.
7. Current admin product management.
8. Current admin order management.
9. Current Flutter Web routing setup.
10. Current hosting / route rewrite setup for direct URL opening.

Do not introduce duplicate concepts if equivalent ones already exist.

If the project already has fields, enums, services, repositories, or database collections for events, product types, order statuses, payment statuses, QR codes, or notifications, reuse them.

Only add new fields if the current architecture cannot support this feature without them.

---

## 3. Recommended Data Model Changes

### 3.1 Product

ISKRY transfer products should use the existing product system.

Add or reuse fields equivalent to:

```text
event_slug: "iskry"
product_type: "transfer"
is_active: true
capacity: 53
```

If the project already has enums, use enums instead of raw strings.

Recommended product fields:

```text
id
title
description
price
currency
event_slug
product_type
capacity
is_active
departure_point optional
departure_datetime optional
arrival_point optional
created_at
updated_at
```

Minimum required product fields:

```text
id
title
price
event_slug
product_type
capacity
is_active
```

### 3.2 Order

Use the existing order system.

For ISKRY transfer orders, add or reuse fields equivalent to:

```text
event_slug: "iskry"
product_type: "transfer"
product_id
quantity
total_amount
contact_telegram
contact_name optional
contact_phone optional
status: "pending"
qr_mode: "single_qr_per_order"
```

Important:

- `quantity` means number of transfer seats.
- One order should have one QR code.
- QR validation must show how many seats are attached to the order.

---

## 4. Product Filtering Logic

The `/iskry` landing must load only products matching:

```text
event_slug == "iskry"
product_type == "transfer"
is_active == true
```

These products must not appear on the main SPACE landing or other public product pages unless explicitly intended.

If the existing code has product repository methods, add a method such as:

```text
getProductsByEventAndType(eventSlug: "iskry", productType: "transfer")
```

or adapt an existing filtering method.

---

## 5. Seat Availability Logic

Each transfer product has a capacity of 53 seats by default.

Available seats must be calculated from paid orders only:

```text
available_places = product.capacity - sum(order.quantity where order.product_id == product.id and order.status == paid)
```

Pending, failed, cancelled, or expired orders must not permanently consume seats unless the existing system already supports temporary reservation.

If the existing project supports temporary pending reservations, use that mechanism carefully and ensure expired pending orders are released.

### Critical requirement

Do not rely only on frontend validation.

Oversell prevention must happen on the backend / database layer as well.

Recommended approaches:

- database transaction;
- atomic counter update;
- server-side validation before payment creation;
- server-side validation before marking order as paid;
- reusable inventory reservation mechanism if it already exists.

---

## 6. Flutter Web Route

Add a new route:

```text
/iskry
```

The route must work when opened directly:

```text
https://spacefestival.fun/iskry
```

Check the current Flutter Web routing mode:

- Navigator 1.0;
- Navigator 2.0;
- GoRouter;
- AutoRoute;
- custom router.

If the hosting requires rewrite rules for Flutter Web, ensure `/iskry` resolves correctly to the Flutter app entry point.

Also add optional payment result routes if needed:

```text
/iskry/success
/iskry/fail
```

If the existing app already has generic success/fail routes, reuse them and pass ISKRY-specific copy/context.

---

## 7. ISKRY Landing UI

Create a responsive Flutter Web page for `/iskry`.

The page must work well on:

- mobile browsers;
- desktop browsers;
- Telegram WebView.

### 7.1 Page Structure

The page should include:

1. Hero section:
   - title: `ISKRY`;
   - subtitle: `Трансфер на событие ISKRY`;
   - note: `После оплаты QR-код придёт в Telegram.`

2. Transfer selection section:
   - list of available transfer products;
   - product card for each transfer;
   - title;
   - description if available;
   - departure point if available;
   - departure datetime if available;
   - price per seat;
   - available seats;
   - sold out state if no seats are available.

3. Seat quantity selector:
   - minimum: 1;
   - maximum: available seats;
   - cannot exceed product capacity;
   - disabled when no seats are available.

4. Contact section:
   - Telegram username, required;
   - name, optional;
   - phone, optional.

5. Summary section:
   - selected transfer;
   - selected quantity;
   - price per seat;
   - total amount.

6. Payment button:
   - label: `Оплатить`;
   - disabled until all required data is valid;
   - creates pending order;
   - starts existing payment flow.

---

## 8. Validation Rules

### 8.1 Telegram

Telegram field is required.

Accept formats:

```text
@username
username
https://t.me/username
t.me/username
```

Normalize to one internal format, preferably:

```text
@username
```

Validation requirements:

- not empty;
- no spaces;
- valid Telegram username characters;
- reasonable username length;
- strip `https://t.me/`, `t.me/`, and leading `@` before normalization.

### 8.2 Quantity

Quantity must be:

```text
quantity >= 1
quantity <= available_places
quantity <= product.capacity
```

For a standard ISKRY bus product:

```text
product.capacity = 53
```

### 8.3 Optional Fields

Name is optional.

Phone is optional.

If phone is filled, apply light validation only. Do not block valid international formats unnecessarily.

---

## 9. Order Creation Flow

When the user clicks `Оплатить`:

1. Validate selected product.
2. Validate quantity.
3. Validate Telegram contact.
4. Re-check product availability on backend / repository layer.
5. Create a pending order.
6. Attach ISKRY transfer metadata to the order.
7. Start existing payment flow for the created order.

Order payload should include equivalent data:

```text
event_slug: "iskry"
product_type: "transfer"
product_id: selectedProduct.id
quantity: selectedQuantity
total_amount: selectedProduct.price * selectedQuantity
contact_telegram: normalizedTelegram
contact_name: optionalName
contact_phone: optionalPhone
status: "pending"
qr_mode: "single_qr_per_order"
```

Use the current project naming conventions and existing models.

---

## 10. Payment Flow

Use the existing Space App payment system.

Do not add a new payment provider.

Expected flow:

1. Pending order is created.
2. User is redirected to the existing payment page/provider.
3. Existing webhook/callback receives payment result.
4. Order status changes to `paid` after successful payment.
5. QR generation flow starts.
6. QR is sent to Telegram.

If the current payment system requires success/fail URLs, configure them for ISKRY:

```text
https://spacefestival.fun/iskry/success
https://spacefestival.fun/iskry/fail
```

or use existing result routes with ISKRY context.

---

## 11. QR Code Flow

For ISKRY transfer orders:

- generate one QR code per paid order;
- do not generate separate QR codes per seat;
- QR must be linked to `order_id`;
- QR validation must show `quantity` seats;
- QR must be sent to the Telegram username provided by the user.

Example:

User buys 4 seats.

Expected result:

```text
order.quantity = 4
one QR code generated
QR is valid for 4 seats
Telegram receives one QR code
```

Use the existing QR-code generation service.

Use the existing Telegram delivery service.

---

## 12. Success and Failure UX

### 12.1 Success Screen

After successful payment, show:

```text
Оплата прошла успешно.
QR-код отправлен в Telegram, который вы указали при оформлении.
Если сообщение не пришло, напишите в поддержку.
```

Route can be:

```text
/iskry/success
```

or an existing generic success route with ISKRY-specific content.

### 12.2 Failure Screen

After failed payment, show:

```text
Оплата не прошла.
Попробуйте ещё раз или напишите в поддержку.
```

Route can be:

```text
/iskry/fail
```

or an existing generic failure route with ISKRY-specific content.

---

## 13. Admin Panel Changes

Extend the existing Space App admin panel.

Do not create a completely separate ISKRY admin unless the project architecture requires it.

### 13.1 Product Admin

Admin must be able to create and edit ISKRY transfer products.

Required admin fields:

```text
Title
Description
Price per seat
Capacity, default 53
Active / inactive
Event: ISKRY
Product type: Transfer
Departure point optional
Departure datetime optional
Arrival point optional
```

If the current admin already supports product creation, add event/product-type support there.

Admin should be able to explicitly set:

```text
event_slug = "iskry"
product_type = "transfer"
```

or choose from UI dropdowns:

```text
Event: ISKRY
Type: Transfer
```

### 13.2 Order Admin

ISKRY transfer orders should appear in the existing order admin.

Add filters:

```text
event_slug = iskry
product_type = transfer
```

For each ISKRY transfer order, admin should see:

```text
transfer product
quantity / number of seats
payment status
Telegram contact
name if filled
phone if filled
QR status
QR resend action if existing notification tools support it
created_at
paid_at
```

Do not break existing Space / Space Up order views.

---

## 14. Oversell Protection

Oversell protection is mandatory.

Frontend validation is not enough.

Implement or reuse backend/database-level protection.

Potential safe approach:

1. When creating pending order, check current availability.
2. When payment is confirmed, check availability again inside a transaction.
3. If paid seats would exceed capacity, prevent confirmation or mark the order for manual review/refund depending on the existing payment architecture.

Preferred approach if supported:

- atomic inventory reservation;
- transaction-based decrement;
- paid seat counter per product;
- reservation expiry for pending orders.

The final implementation must guarantee:

```text
sum(paid_orders.quantity for product) <= product.capacity
```

---

## 15. Suggested Implementation Milestones

### Milestone 1: Architecture Inspection

- Locate product model and repository.
- Locate order model and repository.
- Locate payment service.
- Locate payment webhook/callback.
- Locate QR generation service.
- Locate Telegram QR sending service.
- Locate admin product UI.
- Locate admin order UI.
- Locate Flutter Web routing.

Deliverable:

- short implementation note listing files to modify and services to reuse.

### Milestone 2: Data Model Support

- Add/reuse `event_slug` for products and orders.
- Add/reuse `product_type` for products and orders.
- Add/reuse `capacity` for transfer products.
- Add/reuse `quantity` for order seats.
- Add/reuse QR mode for one QR per order.

Deliverable:

- data model supports ISKRY transfer products and orders.

### Milestone 3: Product Query and Availability

- Add product filtering for ISKRY transfers.
- Add available seat calculation.
- Ensure only paid orders reduce available seat count unless reservation system exists.

Deliverable:

- `/iskry` can fetch only active ISKRY transfer products with available seat counts.

### Milestone 4: Flutter Web Landing

- Add `/iskry` route.
- Build responsive landing UI.
- Add transfer selector.
- Add quantity selector.
- Add Telegram/name/phone form.
- Add order summary.
- Add validation.
- Add disabled/sold-out states.

Deliverable:

- user can fill the form and prepare for payment.

### Milestone 5: Order Creation and Payment Integration

- Create pending transfer order.
- Use existing payment service.
- Send correct amount and metadata.
- Configure success/fail route if needed.

Deliverable:

- clicking `Оплатить` starts real existing payment flow.

### Milestone 6: Payment Callback, QR and Telegram

- On successful payment, mark order paid using existing logic.
- Generate one QR per order.
- Ensure QR knows the quantity of seats.
- Send QR to Telegram using existing service.

Deliverable:

- paid user receives one QR in Telegram.

### Milestone 7: Admin Panel

- Extend product admin for ISKRY transfer products.
- Add default capacity 53.
- Add order filters for ISKRY transfer orders.
- Show quantity, Telegram, optional name/phone and QR status.

Deliverable:

- admin can create products and track transfer orders.

### Milestone 8: Routing and Deployment Checks

- Ensure direct opening of `/iskry` works.
- Check hosting rewrites.
- Check mobile layout.
- Check Telegram WebView.
- Check main SPACE landing is not affected.

Deliverable:

- `/iskry` works in production-like routing conditions.

### Milestone 9: Final QA

Test cases:

1. Active ISKRY transfer product appears on `/iskry`.
2. Inactive ISKRY product does not appear.
3. Non-ISKRY transfer product does not appear.
4. ISKRY product does not appear on main SPACE landing.
5. User cannot submit without Telegram.
6. Telegram formats normalize correctly.
7. User cannot select more seats than available.
8. Product with 0 available seats is sold out.
9. Pending order is created correctly.
10. Payment flow starts correctly.
11. Successful payment marks order as paid.
12. One QR is generated per order.
13. QR represents the correct quantity of seats.
14. QR is sent to Telegram.
15. Admin sees ISKRY transfer order.
16. Admin filters orders by ISKRY / transfer.
17. Oversell is impossible under concurrent purchase attempts.
18. `/iskry` opens directly by URL.
19. `/iskry` works in Telegram WebView.
20. Existing Space / Space Up flows still work.

---

## 16. Acceptance Criteria

The task is complete when:

1. `/iskry` opens as a separate landing page.
2. The landing displays only active ISKRY transfer products.
3. Transfer products are filtered by `event_slug = iskry` and `product_type = transfer` or equivalent existing fields.
4. ISKRY transfer products are hidden from unrelated public product pages.
5. User can select a transfer product.
6. User can select number of seats.
7. Maximum seat quantity is limited by available seats.
8. Product capacity defaults to 53 seats.
9. Telegram contact is required.
10. Name and phone are optional.
11. `Оплатить` creates a pending order.
12. Existing payment flow is used.
13. Successful payment marks the order as paid.
14. One QR code is generated per paid order.
15. QR code is connected to the order and its quantity.
16. QR code is sent to Telegram using existing Telegram QR delivery.
17. Admin can create ISKRY transfer products.
18. Admin can see and filter ISKRY transfer orders.
19. Overselling seats is prevented at backend/database level.
20. Existing Space / Space Up functionality is not broken.

---

## 17. Important Constraints for Codex

Follow these rules strictly:

1. Do not create mock production flows.
2. Do not create a new payment provider.
3. Do not create a new QR system.
4. Do not create a new Telegram sending system.
5. Do not create a separate database.
6. Do not duplicate models if existing models can be extended.
7. Do not break existing Space / Space Up flows.
8. Reuse existing services and coding conventions.
9. Keep code production-ready.
10. Add comments only where they clarify non-obvious business logic.
11. Keep UI adaptive and clean.
12. Ensure direct route opening works for Flutter Web.

---

## 18. Codex Prompt

Use this prompt when starting the implementation:

```text
You are working inside an existing Flutter / Flutter Web project called Space App.

Implement a new separate landing page for ISKRY transfer registration and payment at /iskry.

Before writing code, inspect the existing architecture and identify the current Product model, Order model, payment flow, payment callback/webhook, QR generation flow, Telegram QR delivery flow, admin product management, admin order management, and Flutter Web routing.

Do not create a separate payment system, separate database, separate QR service, separate Telegram delivery service, or duplicate product/order models. Reuse existing Space App infrastructure and extend it carefully.

The /iskry landing must display only active transfer products for event_slug = iskry and product_type = transfer. ISKRY transfer products must not appear on unrelated public Space product pages.

The user flow:
1. User opens /iskry.
2. User selects a transfer product.
3. User selects number of seats.
4. User enters Telegram contact, required.
5. User may optionally enter name and phone.
6. User clicks Оплатить.
7. System creates a pending order.
8. Existing payment flow starts.
9. After successful payment, order becomes paid.
10. System generates one QR code for the whole order.
11. QR code represents the purchased quantity of seats.
12. QR code is sent to the Telegram contact using existing Telegram QR delivery.

Business rules:
- ISKRY currently sells only transfers.
- One bus/product has 53 seats by default.
- One order generates one QR code, even if quantity is greater than 1.
- Prevent overselling seats.
- Frontend validation is not enough; availability must be checked on backend/database layer.
- Use paid orders to calculate occupied seats unless the existing project already has temporary reservation logic.

Admin requirements:
- Extend existing product admin so an admin can create ISKRY transfer products.
- Required fields: title, description, price, capacity default 53, active flag, event ISKRY, product type Transfer.
- Extend existing order admin with filters for event_slug = iskry and product_type = transfer.
- Admin should see product, quantity, payment status, Telegram, optional name, optional phone, QR status.

UI requirements:
- Add route /iskry.
- Page must work on mobile, desktop, and Telegram WebView.
- Show hero, transfer cards, quantity selector, Telegram field, optional name/phone fields, total amount, and Оплатить button.
- Telegram is required and must accept @username, username, https://t.me/username, and t.me/username. Normalize it to a consistent internal format.
- Disable payment if data is invalid or no seats are available.
- Add or reuse success/fail pages with ISKRY-specific text.

Acceptance criteria:
1. /iskry opens directly by URL.
2. Only active ISKRY transfer products appear there.
3. Main Space landing is not affected.
4. User can pay for one or more seats.
5. User cannot buy more seats than available.
6. One paid order generates one QR code.
7. QR is sent to Telegram.
8. Admin can create and manage ISKRY transfer products.
9. Admin can view and filter ISKRY transfer orders.
10. Existing Space / Space Up flows remain working.

Start by producing a short implementation plan listing the files/services you will modify, then implement the feature following the existing project patterns.
```
