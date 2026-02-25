import '../../../core/utils/json_utils.dart';

/// TicketProductModel represents ticket product model.

class TicketProductModel {
  /// TicketProductModel handles ticket product model.
  factory TicketProductModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketProductModel(
      id: asString(map['id']),
      eventId: asInt(map['eventId']),
      name: asString(map['name']),
      type: asString(map['type']).toUpperCase(),
      priceCents: asInt(map['priceCents']),
      inventoryLimit:
          map['inventoryLimit'] == null ? null : asInt(map['inventoryLimit']),
      soldCount: asInt(map['soldCount']),
      isActive: asBool(map['isActive']),
    );
  }

  /// TicketProductModel handles ticket product model.
  TicketProductModel({
    required this.id,
    required this.eventId,
    required this.name,
    required this.type,
    required this.priceCents,
    required this.inventoryLimit,
    required this.soldCount,
    required this.isActive,
  });

  final String id;
  final int eventId;
  final String name;
  final String type;
  final int priceCents;
  final int? inventoryLimit;
  final int soldCount;
  final bool isActive;

  /// label handles internal label behavior.

  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    switch (type) {
      case 'GROUP2':
        return 'Group ticket (2 people)';
      case 'GROUP10':
        return 'Group ticket (10 people)';
      case 'SINGLE':
      default:
        return 'Single ticket';
    }
  }
}

/// TransferProductModel represents transfer product model.

class TransferProductModel {
  /// TransferProductModel handles transfer product model.
  factory TransferProductModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TransferProductModel(
      id: asString(map['id']),
      eventId: asInt(map['eventId']),
      name: asString(map['name']),
      direction: asString(map['direction']).toUpperCase(),
      priceCents: asInt(map['priceCents']),
      info: asMap(map['info']),
      inventoryLimit:
          map['inventoryLimit'] == null ? null : asInt(map['inventoryLimit']),
      soldCount: asInt(map['soldCount']),
      isActive: asBool(map['isActive']),
    );
  }

  /// TransferProductModel handles transfer product model.
  TransferProductModel({
    required this.id,
    required this.eventId,
    required this.name,
    required this.direction,
    required this.priceCents,
    required this.info,
    required this.inventoryLimit,
    required this.soldCount,
    required this.isActive,
  });

  final String id;
  final int eventId;
  final String name;
  final String direction;
  final int priceCents;
  final Map<String, dynamic> info;
  final int? inventoryLimit;
  final int soldCount;
  final bool isActive;

  /// label handles internal label behavior.

  String get label {
    if (name.trim().isNotEmpty) return name.trim();
    switch (direction) {
      case 'BACK':
        return 'One-way back';
      case 'ROUNDTRIP':
        return 'Round trip';
      case 'THERE':
      default:
        return 'One-way there';
    }
  }

  /// infoLabel handles info label.

  String get infoLabel {
    final time = asString(info['time']);
    final pickup = asString(info['pickupPoint']);
    final notes = asString(info['notes']);
    return [time, pickup, notes]
        .where((item) => item.trim().isNotEmpty)
        .join(' · ');
  }
}

/// EventProductsModel represents event products model.

class EventProductsModel {
  /// EventProductsModel handles event products model.
  factory EventProductsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return EventProductsModel(
      tickets: asList(map['tickets']).map(TicketProductModel.fromJson).toList(),
      transfers:
          asList(map['transfers']).map(TransferProductModel.fromJson).toList(),
    );
  }

  /// EventProductsModel handles event products model.
  EventProductsModel({required this.tickets, required this.transfers});

  final List<TicketProductModel> tickets;
  final List<TransferProductModel> transfers;
}

/// PromoValidationModel represents promo validation model.

class PromoValidationModel {
  /// PromoValidationModel handles promo validation model.
  factory PromoValidationModel.fromJson(dynamic json) {
    final map = asMap(json);
    return PromoValidationModel(
      valid: asBool(map['valid']),
      code: asString(map['code']),
      discountType: asString(map['discountType']).toUpperCase(),
      value: asInt(map['value']),
      discountCents: asInt(map['discountCents']),
      totalCents: asInt(map['totalCents']),
      reason: asString(map['reason']),
    );
  }

  /// PromoValidationModel handles promo validation model.
  PromoValidationModel({
    required this.valid,
    required this.code,
    required this.discountType,
    required this.value,
    required this.discountCents,
    required this.totalCents,
    required this.reason,
  });

  final bool valid;
  final String code;
  final String discountType;
  final int value;
  final int discountCents;
  final int totalCents;
  final String reason;
}

/// OrderSelectionModel represents order selection model.

class OrderSelectionModel {
  /// OrderSelectionModel handles order selection model.
  OrderSelectionModel({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  /// toJson handles to json.

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'quantity': quantity,
      };
}

/// CreateOrderPayload represents create order payload.

class CreateOrderPayload {
  /// CreateOrderPayload creates order payload.
  CreateOrderPayload({
    required this.eventId,
    required this.paymentMethod,
    required this.paymentReference,
    required this.ticketItems,
    required this.transferItems,
    required this.promoCode,
  });

  final int eventId;
  final String paymentMethod;
  final String paymentReference;
  final List<OrderSelectionModel> ticketItems;
  final List<OrderSelectionModel> transferItems;
  final String promoCode;

  /// toJson handles to json.

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'eventId': eventId,
      'paymentMethod': paymentMethod,
      'paymentReference': paymentReference,
      'ticketItems': ticketItems.map((item) => item.toJson()).toList(),
      'transferItems': transferItems.map((item) => item.toJson()).toList(),
      'promoCode': promoCode,
    };
  }
}

/// PaymentInstructionsModel represents payment instructions model.

class PaymentInstructionsModel {
  /// PaymentInstructionsModel handles payment instructions model.
  factory PaymentInstructionsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return PaymentInstructionsModel(
      phoneNumber: asString(map['phoneNumber']),
      usdtWallet: asString(map['usdtWallet']),
      usdtNetwork: asString(map['usdtNetwork']),
      usdtMemo: asString(map['usdtMemo']),
      paymentQrData: asString(map['paymentQrData']),
      paymentQrCId: asString(map['paymentQrCId']),
      amountCents: asInt(map['amountCents']),
      currency: asString(map['currency']),
      displayMessage: asString(map['displayMessage']),
    );
  }

  /// PaymentInstructionsModel handles payment instructions model.
  PaymentInstructionsModel({
    required this.phoneNumber,
    required this.usdtWallet,
    required this.usdtNetwork,
    required this.usdtMemo,
    required this.paymentQrData,
    required this.paymentQrCId,
    required this.amountCents,
    required this.currency,
    required this.displayMessage,
  });

  final String phoneNumber;
  final String usdtWallet;
  final String usdtNetwork;
  final String usdtMemo;
  final String paymentQrData;
  final String paymentQrCId;
  final int amountCents;
  final String currency;
  final String displayMessage;
}

/// PaymentSettingsModel represents payment settings model.

class PaymentSettingsModel {
  /// PaymentSettingsModel handles payment settings model.
  factory PaymentSettingsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return PaymentSettingsModel(
      phoneNumber: asString(map['phoneNumber']),
      usdtWallet: asString(map['usdtWallet']),
      usdtNetwork: asString(map['usdtNetwork']),
      usdtMemo: asString(map['usdtMemo']),
      paymentQrData: asString(map['paymentQrData']),
      phoneEnabled: asBool(map['phoneEnabled'], fallback: true),
      usdtEnabled: asBool(map['usdtEnabled'], fallback: true),
      paymentQrEnabled: asBool(map['paymentQrEnabled'], fallback: true),
      sbpEnabled: asBool(map['sbpEnabled'], fallback: true),
      phoneDescription: asString(map['phoneDescription']),
      usdtDescription: asString(map['usdtDescription']),
      qrDescription: asString(map['qrDescription']),
      sbpDescription: asString(map['sbpDescription']),
    );
  }

  /// PaymentSettingsModel handles payment settings model.
  PaymentSettingsModel({
    required this.phoneNumber,
    required this.usdtWallet,
    required this.usdtNetwork,
    required this.usdtMemo,
    required this.paymentQrData,
    required this.phoneEnabled,
    required this.usdtEnabled,
    required this.paymentQrEnabled,
    required this.sbpEnabled,
    required this.phoneDescription,
    required this.usdtDescription,
    required this.qrDescription,
    required this.sbpDescription,
  });

  final String phoneNumber;
  final String usdtWallet;
  final String usdtNetwork;
  final String usdtMemo;
  final String paymentQrData;
  final bool phoneEnabled;
  final bool usdtEnabled;
  final bool paymentQrEnabled;
  final bool sbpEnabled;
  final String phoneDescription;
  final String usdtDescription;
  final String qrDescription;
  final String sbpDescription;

  /// descriptionForMethod handles description for method.

  String descriptionForMethod(String method) {
    switch (method.toUpperCase()) {
      case 'PHONE':
        return phoneDescription;
      case 'USDT':
        return usdtDescription;
      case 'PAYMENT_QR':
        return qrDescription;
      case 'TOCHKA_SBP_QR':
        return sbpDescription;
      default:
        return '';
    }
  }

  /// isMethodEnabled reports whether method enabled condition is met.

  bool isMethodEnabled(String method) {
    switch (method.toUpperCase()) {
      case 'PHONE':
        return phoneEnabled;
      case 'USDT':
        return usdtEnabled;
      case 'PAYMENT_QR':
        return paymentQrEnabled;
      case 'TOCHKA_SBP_QR':
        return sbpEnabled;
      default:
        return false;
    }
  }
}

/// OrderModel represents order model.

class OrderModel {
  /// OrderModel handles order model.
  factory OrderModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderModel(
      id: asString(map['id']),
      userId: asInt(map['userId']),
      eventId: asInt(map['eventId']),
      eventTitle: asString(map['eventTitle']),
      status: asString(map['status']).toUpperCase(),
      paymentMethod: asString(map['paymentMethod']).toUpperCase(),
      paymentReference: asString(map['paymentReference']),
      paymentNotes: asString(map['paymentNotes']),
      subtotalCents: asInt(map['subtotalCents']),
      discountCents: asInt(map['discountCents']),
      totalCents: asInt(map['totalCents']),
      currency: asString(map['currency']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
      confirmedAt: asDateTime(map['confirmedAt']),
      canceledAt: asDateTime(map['canceledAt']),
      redeemedAt: asDateTime(map['redeemedAt']),
    );
  }

  /// OrderModel handles order model.
  OrderModel({
    required this.id,
    required this.userId,
    required this.eventId,
    required this.eventTitle,
    required this.status,
    required this.paymentMethod,
    required this.paymentReference,
    required this.paymentNotes,
    required this.subtotalCents,
    required this.discountCents,
    required this.totalCents,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.canceledAt,
    required this.redeemedAt,
  });

  final String id;
  final int userId;
  final int eventId;
  final String eventTitle;
  final String status;
  final String paymentMethod;
  final String paymentReference;
  final String paymentNotes;
  final int subtotalCents;
  final int discountCents;
  final int totalCents;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? confirmedAt;
  final DateTime? canceledAt;
  final DateTime? redeemedAt;
}

/// OrderUserModel represents order user model.

class OrderUserModel {
  /// OrderUserModel handles order user model.
  factory OrderUserModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderUserModel(
      id: asInt(map['id']),
      telegramId: asInt(map['telegramId']),
      firstName: asString(map['firstName']),
      lastName: asString(map['lastName']),
      username: asString(map['username']),
    );
  }

  /// OrderUserModel handles order user model.
  OrderUserModel({
    required this.id,
    required this.telegramId,
    required this.firstName,
    required this.lastName,
    required this.username,
  });

  final int id;
  final int telegramId;
  final String firstName;
  final String lastName;
  final String username;

  /// usernameLabel handles username label.
  String get usernameLabel {
    final normalized = username.trim();
    if (normalized.isEmpty) return '';
    return '@$normalized';
  }

  /// displayName handles display name.

  String get displayName {
    final fullName = [firstName, lastName]
        .where((item) => item.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (fullName.isNotEmpty) return fullName;
    if (username.trim().isNotEmpty) return '@${username.trim()}';
    return '#$id';
  }
}

/// OrderItemModel represents order item model.

class OrderItemModel {
  /// OrderItemModel handles order item model.
  factory OrderItemModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderItemModel(
      id: asInt(map['id']),
      orderId: asString(map['orderId']),
      itemType: asString(map['itemType']).toUpperCase(),
      productId: asString(map['productId']),
      productRef: asString(map['productRef']),
      quantity: asInt(map['quantity']),
      unitPriceCents: asInt(map['unitPriceCents']),
      lineTotalCents: asInt(map['lineTotalCents']),
      meta: asMap(map['meta']),
    );
  }

  /// OrderItemModel handles order item model.
  OrderItemModel({
    required this.id,
    required this.orderId,
    required this.itemType,
    required this.productId,
    required this.productRef,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
    required this.meta,
  });

  final int id;
  final String orderId;
  final String itemType;
  final String productId;
  final String productRef;
  final int quantity;
  final int unitPriceCents;
  final int lineTotalCents;
  final Map<String, dynamic> meta;
}

/// TicketModel represents ticket model.

class TicketModel {
  /// TicketModel handles ticket model.
  factory TicketModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketModel(
      id: asString(map['id']),
      orderId: asString(map['orderId']),
      orderStatus: asString(map['orderStatus']).toUpperCase(),
      userId: asInt(map['userId']),
      eventId: asInt(map['eventId']),
      ticketType: asString(map['ticketType']).toUpperCase(),
      quantity: asInt(map['quantity']),
      qrPayload: asString(map['qrPayload']),
      redeemedAt: asDateTime(map['redeemedAt']),
      createdAt: asDateTime(map['createdAt']),
    );
  }

  /// TicketModel handles ticket model.
  TicketModel({
    required this.id,
    required this.orderId,
    required this.orderStatus,
    required this.userId,
    required this.eventId,
    required this.ticketType,
    required this.quantity,
    required this.qrPayload,
    required this.redeemedAt,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String orderStatus;
  final int userId;
  final int eventId;
  final String ticketType;
  final int quantity;
  final String qrPayload;
  final DateTime? redeemedAt;
  final DateTime? createdAt;

  /// status handles internal status behavior.

  String get status {
    if (orderStatus.trim().isNotEmpty) return orderStatus;
    return redeemedAt == null ? 'PAID' : 'REDEEMED';
  }
}

/// OrderDetailModel represents order detail model.

class OrderDetailModel {
  /// OrderDetailModel handles order detail model.
  factory OrderDetailModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderDetailModel(
      order: OrderModel.fromJson(map['order']),
      user: map['user'] == null ? null : OrderUserModel.fromJson(map['user']),
      items: asList(map['items']).map(OrderItemModel.fromJson).toList(),
      tickets: asList(map['tickets']).map(TicketModel.fromJson).toList(),
      paymentInstructions:
          PaymentInstructionsModel.fromJson(map['paymentInstructions']),
    );
  }

  /// OrderDetailModel handles order detail model.
  OrderDetailModel({
    required this.order,
    required this.user,
    required this.items,
    required this.tickets,
    required this.paymentInstructions,
  });

  final OrderModel order;
  final OrderUserModel? user;
  final List<OrderItemModel> items;
  final List<TicketModel> tickets;
  final PaymentInstructionsModel paymentInstructions;
}

/// OrderSummaryModel represents order summary model.

class OrderSummaryModel {
  /// OrderSummaryModel handles order summary model.
  factory OrderSummaryModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderSummaryModel(
      order: OrderModel.fromJson(map),
      user: map['user'] == null ? null : OrderUserModel.fromJson(map['user']),
    );
  }

  /// OrderSummaryModel handles order summary model.
  OrderSummaryModel({required this.order, required this.user});

  final OrderModel order;
  final OrderUserModel? user;
}

/// OrdersListModel represents orders list model.

class OrdersListModel {
  /// OrdersListModel handles orders list model.
  factory OrdersListModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrdersListModel(
      items: asList(map['items']).map(OrderSummaryModel.fromJson).toList(),
      total: asInt(map['total']),
    );
  }

  /// OrdersListModel handles orders list model.
  OrdersListModel({required this.items, required this.total});

  final List<OrderSummaryModel> items;
  final int total;
}

/// AdminBotMessageModel represents admin bot message model.

class AdminBotMessageModel {
  /// AdminBotMessageModel handles admin bot message model.
  factory AdminBotMessageModel.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminBotMessageModel(
      id: asInt(map['id']),
      chatId: asInt(map['chatId']),
      direction: asString(map['direction']).toUpperCase(),
      text: asString(map['text']),
      telegramMessageId: map['telegramMessageId'] == null
          ? null
          : asInt(map['telegramMessageId']),
      senderTelegramId: map['senderTelegramId'] == null
          ? null
          : asInt(map['senderTelegramId']),
      senderUsername: asString(map['senderUsername']),
      senderFirstName: asString(map['senderFirstName']),
      senderLastName: asString(map['senderLastName']),
      adminTelegramId:
          map['adminTelegramId'] == null ? null : asInt(map['adminTelegramId']),
      userId: map['userId'] == null ? null : asInt(map['userId']),
      userUsername: asString(map['userUsername']),
      userFirstName: asString(map['userFirstName']),
      userLastName: asString(map['userLastName']),
      createdAt: asDateTime(map['createdAt']),
    );
  }

  /// AdminBotMessageModel handles admin bot message model.

  AdminBotMessageModel({
    required this.id,
    required this.chatId,
    required this.direction,
    required this.text,
    required this.telegramMessageId,
    required this.senderTelegramId,
    required this.senderUsername,
    required this.senderFirstName,
    required this.senderLastName,
    required this.adminTelegramId,
    required this.userId,
    required this.userUsername,
    required this.userFirstName,
    required this.userLastName,
    required this.createdAt,
  });

  final int id;
  final int chatId;
  final String direction;
  final String text;
  final int? telegramMessageId;
  final int? senderTelegramId;
  final String senderUsername;
  final String senderFirstName;
  final String senderLastName;
  final int? adminTelegramId;
  final int? userId;
  final String userUsername;
  final String userFirstName;
  final String userLastName;
  final DateTime? createdAt;

  /// isIncoming reports whether incoming condition is met.

  bool get isIncoming => direction == 'INCOMING';

  /// contactLabel handles contact label.

  String get contactLabel {
    if (userUsername.trim().isNotEmpty) return '@${userUsername.trim()}';
    if (senderUsername.trim().isNotEmpty) return '@${senderUsername.trim()}';

    final userFullName = [userFirstName, userLastName]
        .where((item) => item.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (userFullName.isNotEmpty) return userFullName;

    final senderFullName = [senderFirstName, senderLastName]
        .where((item) => item.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (senderFullName.isNotEmpty) return senderFullName;
    if (userId != null && userId! > 0) return 'Пользователь #${userId!}';
    return 'Пользователь';
  }
}

/// AdminBotMessagesListModel represents admin bot messages list model.

class AdminBotMessagesListModel {
  /// AdminBotMessagesListModel handles admin bot messages list model.
  factory AdminBotMessagesListModel.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminBotMessagesListModel(
      items: asList(map['items']).map(AdminBotMessageModel.fromJson).toList(),
      total: asInt(map['total']),
    );
  }

  /// AdminBotMessagesListModel handles admin bot messages list model.

  AdminBotMessagesListModel({required this.items, required this.total});

  final List<AdminBotMessageModel> items;
  final int total;
}

/// MyTicketsModel represents my tickets model.

class MyTicketsModel {
  /// MyTicketsModel handles my tickets model.
  factory MyTicketsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return MyTicketsModel(
      items: asList(map['items']).map(TicketModel.fromJson).toList(),
    );
  }

  /// MyTicketsModel handles my tickets model.
  MyTicketsModel({required this.items});

  final List<TicketModel> items;
}

/// AdminStatsBreakdownModel represents admin stats breakdown model.

class AdminStatsBreakdownModel {
  /// AdminStatsBreakdownModel handles admin stats breakdown model.
  factory AdminStatsBreakdownModel.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminStatsBreakdownModel(
      eventId: map['eventId'] == null ? null : asInt(map['eventId']),
      eventTitle: asString(map['eventTitle']),
      purchasedAmountCents: asInt(map['purchasedAmountCents']),
      redeemedAmountCents: asInt(map['redeemedAmountCents']),
      checkedInTickets: asInt(map['checkedInTickets']),
      checkedInPeople: asInt(map['checkedInPeople']),
      ticketTypeCounts: _parseCountMap(map['ticketTypeCounts']),
      transferDirectionCounts: _parseCountMap(map['transferDirectionCounts']),
    );
  }

  /// AdminStatsBreakdownModel handles admin stats breakdown model.
  AdminStatsBreakdownModel({
    required this.eventId,
    required this.eventTitle,
    required this.purchasedAmountCents,
    required this.redeemedAmountCents,
    required this.checkedInTickets,
    required this.checkedInPeople,
    required this.ticketTypeCounts,
    required this.transferDirectionCounts,
  });

  final int? eventId;
  final String eventTitle;
  final int purchasedAmountCents;
  final int redeemedAmountCents;
  final int checkedInTickets;
  final int checkedInPeople;
  final Map<String, int> ticketTypeCounts;
  final Map<String, int> transferDirectionCounts;

  /// _parseCountMap parses count map.

  static Map<String, int> _parseCountMap(dynamic value) {
    final source = asMap(value);
    return source.map((key, item) => MapEntry(key.toUpperCase(), asInt(item)));
  }
}

/// AdminStatsModel represents admin stats model.

class AdminStatsModel {
  /// AdminStatsModel handles admin stats model.
  factory AdminStatsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminStatsModel(
      global: AdminStatsBreakdownModel.fromJson(map['global']),
      events:
          asList(map['events']).map(AdminStatsBreakdownModel.fromJson).toList(),
    );
  }

  /// AdminStatsModel handles admin stats model.
  AdminStatsModel({required this.global, required this.events});

  final AdminStatsBreakdownModel global;
  final List<AdminStatsBreakdownModel> events;
}

/// TicketRedeemResultModel represents ticket redeem result model.

class TicketRedeemResultModel {
  /// TicketRedeemResultModel handles ticket redeem result model.
  factory TicketRedeemResultModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketRedeemResultModel(
      ticket: TicketModel.fromJson(map['ticket']),
      orderStatus: asString(map['orderStatus']).toUpperCase(),
    );
  }

  /// TicketRedeemResultModel handles ticket redeem result model.
  TicketRedeemResultModel({required this.ticket, required this.orderStatus});

  final TicketModel ticket;
  final String orderStatus;
}

/// SbpQrModel represents sbp qr model.

class SbpQrModel {
  /// SbpQrModel handles sbp qr model.
  factory SbpQrModel.fromJson(dynamic json) {
    final map = asMap(json);
    return SbpQrModel(
      id: asString(map['id']),
      orderId: asString(map['orderId']),
      qrcId: asString(map['qrcId']),
      payload: asString(map['payload']),
      merchantId: asString(map['merchantId']),
      accountId: asString(map['accountId']),
      status: asString(map['status']),
      createdAt: asDateTime(map['createdAt']),
      updatedAt: asDateTime(map['updatedAt']),
    );
  }

  /// SbpQrModel handles sbp qr model.
  SbpQrModel({
    required this.id,
    required this.orderId,
    required this.qrcId,
    required this.payload,
    required this.merchantId,
    required this.accountId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String orderId;
  final String qrcId;
  final String payload;
  final String merchantId;
  final String accountId;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// CreateSbpQrOrderResponseModel represents create sbp qr order response model.

class CreateSbpQrOrderResponseModel {
  /// CreateSbpQrOrderResponseModel creates sbp qr order response model.
  factory CreateSbpQrOrderResponseModel.fromJson(dynamic json) {
    final map = asMap(json);
    return CreateSbpQrOrderResponseModel(
      order: OrderDetailModel.fromJson(map['order']),
      sbpQr: SbpQrModel.fromJson(map['sbpQr']),
    );
  }

  /// CreateSbpQrOrderResponseModel creates sbp qr order response model.
  CreateSbpQrOrderResponseModel({
    required this.order,
    required this.sbpQr,
  });

  final OrderDetailModel order;
  final SbpQrModel sbpQr;
}

/// SbpQrStatusResponseModel represents sbp qr status response model.

class SbpQrStatusResponseModel {
  /// SbpQrStatusResponseModel handles sbp qr status response model.
  factory SbpQrStatusResponseModel.fromJson(dynamic json) {
    final map = asMap(json);
    return SbpQrStatusResponseModel(
      orderId: asString(map['orderId']),
      qrcId: asString(map['qrcId']),
      paymentStatus: asString(map['paymentStatus']),
      orderStatus: asString(map['orderStatus']).toUpperCase(),
      paid: asBool(map['paid']),
      unknown: asBool(map['unknown']),
      message: asString(map['message']),
      detail: map['detail'] == null
          ? null
          : OrderDetailModel.fromJson(map['detail']),
    );
  }

  /// SbpQrStatusResponseModel handles sbp qr status response model.
  SbpQrStatusResponseModel({
    required this.orderId,
    required this.qrcId,
    required this.paymentStatus,
    required this.orderStatus,
    required this.paid,
    required this.unknown,
    required this.message,
    required this.detail,
  });

  final String orderId;
  final String qrcId;
  final String paymentStatus;
  final String orderStatus;
  final bool paid;
  final bool unknown;
  final String message;
  final OrderDetailModel? detail;
}
