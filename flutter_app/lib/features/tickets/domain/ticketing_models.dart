import '../../../core/utils/json_utils.dart';

class TicketProductModel {

  factory TicketProductModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketProductModel(
      id: asString(map['id']),
      eventId: asInt(map['eventId']),
      type: asString(map['type']).toUpperCase(),
      priceCents: asInt(map['priceCents']),
      inventoryLimit:
          map['inventoryLimit'] == null ? null : asInt(map['inventoryLimit']),
      soldCount: asInt(map['soldCount']),
      isActive: asBool(map['isActive']),
    );
  }
  TicketProductModel({
    required this.id,
    required this.eventId,
    required this.type,
    required this.priceCents,
    required this.inventoryLimit,
    required this.soldCount,
    required this.isActive,
  });

  final String id;
  final int eventId;
  final String type;
  final int priceCents;
  final int? inventoryLimit;
  final int soldCount;
  final bool isActive;

  String get label {
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

class TransferProductModel {

  factory TransferProductModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TransferProductModel(
      id: asString(map['id']),
      eventId: asInt(map['eventId']),
      direction: asString(map['direction']).toUpperCase(),
      priceCents: asInt(map['priceCents']),
      info: asMap(map['info']),
      inventoryLimit:
          map['inventoryLimit'] == null ? null : asInt(map['inventoryLimit']),
      soldCount: asInt(map['soldCount']),
      isActive: asBool(map['isActive']),
    );
  }
  TransferProductModel({
    required this.id,
    required this.eventId,
    required this.direction,
    required this.priceCents,
    required this.info,
    required this.inventoryLimit,
    required this.soldCount,
    required this.isActive,
  });

  final String id;
  final int eventId;
  final String direction;
  final int priceCents;
  final Map<String, dynamic> info;
  final int? inventoryLimit;
  final int soldCount;
  final bool isActive;

  String get label {
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

  String get infoLabel {
    final time = asString(info['time']);
    final pickup = asString(info['pickupPoint']);
    final notes = asString(info['notes']);
    return [time, pickup, notes]
        .where((item) => item.trim().isNotEmpty)
        .join(' · ');
  }
}

class EventProductsModel {

  factory EventProductsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return EventProductsModel(
      tickets: asList(map['tickets']).map(TicketProductModel.fromJson).toList(),
      transfers:
          asList(map['transfers']).map(TransferProductModel.fromJson).toList(),
    );
  }
  EventProductsModel({required this.tickets, required this.transfers});

  final List<TicketProductModel> tickets;
  final List<TransferProductModel> transfers;
}

class PromoValidationModel {

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

class OrderSelectionModel {
  OrderSelectionModel({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'productId': productId,
        'quantity': quantity,
      };
}

class CreateOrderPayload {
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

class PaymentInstructionsModel {

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

class PaymentSettingsModel {

  factory PaymentSettingsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return PaymentSettingsModel(
      phoneNumber: asString(map['phoneNumber']),
      usdtWallet: asString(map['usdtWallet']),
      usdtNetwork: asString(map['usdtNetwork']),
      usdtMemo: asString(map['usdtMemo']),
      phoneDescription: asString(map['phoneDescription']),
      usdtDescription: asString(map['usdtDescription']),
      qrDescription: asString(map['qrDescription']),
      sbpDescription: asString(map['sbpDescription']),
    );
  }
  PaymentSettingsModel({
    required this.phoneNumber,
    required this.usdtWallet,
    required this.usdtNetwork,
    required this.usdtMemo,
    required this.phoneDescription,
    required this.usdtDescription,
    required this.qrDescription,
    required this.sbpDescription,
  });

  final String phoneNumber;
  final String usdtWallet;
  final String usdtNetwork;
  final String usdtMemo;
  final String phoneDescription;
  final String usdtDescription;
  final String qrDescription;
  final String sbpDescription;

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
}

class OrderModel {

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

class OrderUserModel {

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

class OrderItemModel {

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

class TicketModel {

  factory TicketModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketModel(
      id: asString(map['id']),
      orderId: asString(map['orderId']),
      userId: asInt(map['userId']),
      eventId: asInt(map['eventId']),
      ticketType: asString(map['ticketType']).toUpperCase(),
      quantity: asInt(map['quantity']),
      qrPayload: asString(map['qrPayload']),
      redeemedAt: asDateTime(map['redeemedAt']),
      createdAt: asDateTime(map['createdAt']),
    );
  }
  TicketModel({
    required this.id,
    required this.orderId,
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
  final int userId;
  final int eventId;
  final String ticketType;
  final int quantity;
  final String qrPayload;
  final DateTime? redeemedAt;
  final DateTime? createdAt;

  String get status => redeemedAt == null ? 'PAID' : 'REDEEMED';
}

class OrderDetailModel {

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

class OrderSummaryModel {

  factory OrderSummaryModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrderSummaryModel(
      order: OrderModel.fromJson(map),
      user: map['user'] == null ? null : OrderUserModel.fromJson(map['user']),
    );
  }
  OrderSummaryModel({required this.order, required this.user});

  final OrderModel order;
  final OrderUserModel? user;
}

class OrdersListModel {

  factory OrdersListModel.fromJson(dynamic json) {
    final map = asMap(json);
    return OrdersListModel(
      items: asList(map['items']).map(OrderSummaryModel.fromJson).toList(),
      total: asInt(map['total']),
    );
  }
  OrdersListModel({required this.items, required this.total});

  final List<OrderSummaryModel> items;
  final int total;
}

class MyTicketsModel {

  factory MyTicketsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return MyTicketsModel(
      items: asList(map['items']).map(TicketModel.fromJson).toList(),
    );
  }
  MyTicketsModel({required this.items});

  final List<TicketModel> items;
}

class AdminStatsBreakdownModel {

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

  static Map<String, int> _parseCountMap(dynamic value) {
    final source = asMap(value);
    return source.map((key, item) => MapEntry(key.toUpperCase(), asInt(item)));
  }
}

class AdminStatsModel {

  factory AdminStatsModel.fromJson(dynamic json) {
    final map = asMap(json);
    return AdminStatsModel(
      global: AdminStatsBreakdownModel.fromJson(map['global']),
      events:
          asList(map['events']).map(AdminStatsBreakdownModel.fromJson).toList(),
    );
  }
  AdminStatsModel({required this.global, required this.events});

  final AdminStatsBreakdownModel global;
  final List<AdminStatsBreakdownModel> events;
}

class TicketRedeemResultModel {

  factory TicketRedeemResultModel.fromJson(dynamic json) {
    final map = asMap(json);
    return TicketRedeemResultModel(
      ticket: TicketModel.fromJson(map['ticket']),
      orderStatus: asString(map['orderStatus']).toUpperCase(),
    );
  }
  TicketRedeemResultModel({required this.ticket, required this.orderStatus});

  final TicketModel ticket;
  final String orderStatus;
}

class SbpQrModel {

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

class CreateSbpQrOrderResponseModel {

  factory CreateSbpQrOrderResponseModel.fromJson(dynamic json) {
    final map = asMap(json);
    return CreateSbpQrOrderResponseModel(
      order: OrderDetailModel.fromJson(map['order']),
      sbpQr: SbpQrModel.fromJson(map['sbpQr']),
    );
  }
  CreateSbpQrOrderResponseModel({
    required this.order,
    required this.sbpQr,
  });

  final OrderDetailModel order;
  final SbpQrModel sbpQr;
}

class SbpQrStatusResponseModel {

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
