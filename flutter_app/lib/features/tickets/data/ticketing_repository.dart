import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/providers.dart';
import '../../../core/utils/json_utils.dart';
import '../domain/ticketing_models.dart';

class TicketingRepository {
  TicketingRepository(this._ref);

  final Ref _ref;

  Future<EventProductsModel> getEventProducts({
    required String token,
    required int eventId,
  }) {
    return _ref.read(apiClientProvider).get<EventProductsModel>(
          '/events/$eventId/products',
          token: token,
          decoder: EventProductsModel.fromJson,
          retry: false,
        );
  }

  Future<PromoValidationModel> validatePromo({
    required String token,
    required int eventId,
    required String code,
    required int subtotalCents,
  }) {
    return _ref.read(apiClientProvider).post<PromoValidationModel>(
          '/promo-codes/validate',
          token: token,
          body: <String, dynamic>{
            'eventId': eventId,
            'code': code.trim(),
            'subtotalCents': subtotalCents,
          },
          decoder: PromoValidationModel.fromJson,
        );
  }

  Future<OrderDetailModel> createOrder({
    required String token,
    required CreateOrderPayload payload,
  }) {
    return _ref.read(apiClientProvider).post<OrderDetailModel>(
          '/orders',
          token: token,
          body: payload.toJson(),
          decoder: OrderDetailModel.fromJson,
        );
  }

  Future<CreateSbpQrOrderResponseModel> createSbpQrOrder({
    required String token,
    required CreateOrderPayload payload,
    String redirectUrl = '',
  }) {
    return _ref.read(apiClientProvider).post<CreateSbpQrOrderResponseModel>(
          '/payments/sbp/qr/create',
          token: token,
          body: <String, dynamic>{
            'eventId': payload.eventId,
            'ticketItems':
                payload.ticketItems.map((item) => item.toJson()).toList(),
            'transferItems':
                payload.transferItems.map((item) => item.toJson()).toList(),
            'promoCode': payload.promoCode,
            if (redirectUrl.trim().isNotEmpty)
              'redirectUrl': redirectUrl.trim(),
          },
          decoder: CreateSbpQrOrderResponseModel.fromJson,
        );
  }

  Future<SbpQrStatusResponseModel> getSbpQrStatus({
    required String token,
    required String orderId,
  }) {
    return _ref.read(apiClientProvider).get<SbpQrStatusResponseModel>(
          '/payments/sbp/qr/$orderId/status',
          token: token,
          decoder: SbpQrStatusResponseModel.fromJson,
          retry: false,
        );
  }

  Future<PaymentSettingsModel> getPaymentSettings({
    required String token,
  }) {
    return _ref.read(apiClientProvider).get<PaymentSettingsModel>(
          '/payments/settings',
          token: token,
          decoder: PaymentSettingsModel.fromJson,
          retry: false,
        );
  }

  Future<PaymentSettingsModel> getAdminPaymentSettings({
    required String token,
  }) {
    return _ref.read(apiClientProvider).get<PaymentSettingsModel>(
          '/admin/payment-settings',
          token: token,
          decoder: PaymentSettingsModel.fromJson,
          retry: false,
        );
  }

  Future<PaymentSettingsModel> upsertAdminPaymentSettings({
    required String token,
    String? phoneNumber,
    String? usdtWallet,
    String? usdtNetwork,
    String? usdtMemo,
    String? paymentQrData,
    String? phoneDescription,
    String? usdtDescription,
    String? qrDescription,
    String? sbpDescription,
  }) {
    return _ref.read(apiClientProvider).post<PaymentSettingsModel>(
          '/admin/payment-settings',
          token: token,
          body: <String, dynamic>{
            if (phoneNumber != null) 'phoneNumber': phoneNumber.trim(),
            if (usdtWallet != null) 'usdtWallet': usdtWallet.trim(),
            if (usdtNetwork != null) 'usdtNetwork': usdtNetwork.trim(),
            if (usdtMemo != null) 'usdtMemo': usdtMemo.trim(),
            if (paymentQrData != null) 'paymentQrData': paymentQrData.trim(),
            if (phoneDescription != null)
              'phoneDescription': phoneDescription.trim(),
            if (usdtDescription != null)
              'usdtDescription': usdtDescription.trim(),
            if (qrDescription != null) 'qrDescription': qrDescription.trim(),
            if (sbpDescription != null) 'sbpDescription': sbpDescription.trim(),
          },
          decoder: PaymentSettingsModel.fromJson,
        );
  }

  Future<OrdersListModel> listMyOrders({
    required String token,
    int limit = 50,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<OrdersListModel>(
          '/orders/my',
          token: token,
          query: <String, dynamic>{
            'limit': limit,
            'offset': offset,
          },
          decoder: OrdersListModel.fromJson,
        );
  }

  Future<MyTicketsModel> listMyTickets({
    required String token,
    int? eventId,
  }) {
    return _ref.read(apiClientProvider).get<MyTicketsModel>(
          '/tickets/my',
          token: token,
          query: <String, dynamic>{
            if (eventId != null && eventId > 0) 'event_id': eventId,
          },
          decoder: MyTicketsModel.fromJson,
        );
  }

  Future<OrdersListModel> listAdminOrders({
    required String token,
    int? eventId,
    String? status,
    String? from,
    String? to,
    int limit = 100,
    int offset = 0,
  }) {
    return _ref.read(apiClientProvider).get<OrdersListModel>(
          '/admin/orders',
          token: token,
          query: <String, dynamic>{
            if (eventId != null && eventId > 0) 'event_id': eventId,
            if ((status ?? '').trim().isNotEmpty)
              'status': status!.trim().toUpperCase(),
            if ((from ?? '').trim().isNotEmpty) 'from': from!.trim(),
            if ((to ?? '').trim().isNotEmpty) 'to': to!.trim(),
            'limit': limit,
            'offset': offset,
          },
          decoder: OrdersListModel.fromJson,
        );
  }

  Future<OrderDetailModel> getAdminOrder({
    required String token,
    required String orderId,
  }) {
    return _ref.read(apiClientProvider).get<OrderDetailModel>(
          '/admin/orders/$orderId',
          token: token,
          decoder: OrderDetailModel.fromJson,
          retry: false,
        );
  }

  Future<OrderDetailModel> confirmOrder({
    required String token,
    required String orderId,
  }) {
    return _ref.read(apiClientProvider).post<OrderDetailModel>(
          '/admin/orders/$orderId/confirm',
          token: token,
          body: const <String, dynamic>{},
          decoder: OrderDetailModel.fromJson,
        );
  }

  Future<OrderDetailModel> cancelOrder({
    required String token,
    required String orderId,
    String reason = '',
  }) {
    return _ref.read(apiClientProvider).post<OrderDetailModel>(
          '/orders/$orderId/cancel',
          token: token,
          body: <String, dynamic>{
            if (reason.trim().isNotEmpty) 'reason': reason.trim(),
          },
          decoder: OrderDetailModel.fromJson,
        );
  }

  Future<TicketRedeemResultModel> redeemTicket({
    required String token,
    required String ticketId,
    String qrPayload = '',
  }) {
    return _ref.read(apiClientProvider).post<TicketRedeemResultModel>(
          '/admin/tickets/redeem',
          token: token,
          body: <String, dynamic>{
            if (ticketId.trim().isNotEmpty) 'ticketId': ticketId.trim(),
            if (qrPayload.trim().isNotEmpty) 'qrPayload': qrPayload.trim(),
          },
          decoder: TicketRedeemResultModel.fromJson,
        );
  }

  Future<AdminStatsModel> getAdminStats({
    required String token,
    int? eventId,
  }) {
    return _ref.read(apiClientProvider).get<AdminStatsModel>(
          '/admin/stats',
          token: token,
          query: <String, dynamic>{
            if (eventId != null && eventId > 0) 'event_id': eventId,
          },
          decoder: AdminStatsModel.fromJson,
        );
  }

  Future<List<TicketProductModel>> listAdminTicketProducts({
    required String token,
    int? eventId,
    bool? active,
  }) {
    return _ref.read(apiClientProvider).get<List<TicketProductModel>>(
      '/admin/products/tickets',
      token: token,
      query: <String, dynamic>{
        if (eventId != null && eventId > 0) 'event_id': eventId,
        if (active != null) 'active': active,
      },
      decoder: (data) {
        final map = asMap(data);
        return asList(map['items']).map(TicketProductModel.fromJson).toList();
      },
    );
  }

  Future<TicketProductModel> createAdminTicketProduct({
    required String token,
    required int eventId,
    required String type,
    String name = '',
    required int priceCents,
    int? inventoryLimit,
    bool isActive = true,
  }) {
    return _ref.read(apiClientProvider).post<TicketProductModel>(
          '/admin/products/tickets',
          token: token,
          body: <String, dynamic>{
            'eventId': eventId,
            'name': name.trim(),
            'type': type.toUpperCase(),
            'priceCents': priceCents,
            if (inventoryLimit != null && inventoryLimit > 0)
              'inventoryLimit': inventoryLimit,
            'isActive': isActive,
          },
          decoder: TicketProductModel.fromJson,
        );
  }

  Future<TicketProductModel> patchAdminTicketProduct({
    required String token,
    required String productId,
    int? priceCents,
    int? inventoryLimit,
    bool? isActive,
  }) {
    return _ref.read(apiClientProvider).patch<TicketProductModel>(
          '/admin/products/tickets/$productId',
          token: token,
          body: <String, dynamic>{
            if (priceCents != null) 'priceCents': priceCents,
            if (inventoryLimit != null) 'inventoryLimit': inventoryLimit,
            if (isActive != null) 'isActive': isActive,
          },
          decoder: TicketProductModel.fromJson,
        );
  }

  Future<void> deleteAdminTicketProduct({
    required String token,
    required String productId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          '/admin/products/tickets/$productId',
          token: token,
          decoder: (_) {},
        );
  }

  Future<List<TransferProductModel>> listAdminTransferProducts({
    required String token,
    int? eventId,
    bool? active,
  }) {
    return _ref.read(apiClientProvider).get<List<TransferProductModel>>(
      '/admin/products/transfers',
      token: token,
      query: <String, dynamic>{
        if (eventId != null && eventId > 0) 'event_id': eventId,
        if (active != null) 'active': active,
      },
      decoder: (data) {
        final map = asMap(data);
        return asList(map['items']).map(TransferProductModel.fromJson).toList();
      },
    );
  }

  Future<TransferProductModel> createAdminTransferProduct({
    required String token,
    required int eventId,
    required String direction,
    String name = '',
    required int priceCents,
    Map<String, dynamic> info = const <String, dynamic>{},
    int? inventoryLimit,
    bool isActive = true,
  }) {
    return _ref.read(apiClientProvider).post<TransferProductModel>(
          '/admin/products/transfers',
          token: token,
          body: <String, dynamic>{
            'eventId': eventId,
            'name': name.trim(),
            'direction': direction.toUpperCase(),
            'priceCents': priceCents,
            'info': info,
            if (inventoryLimit != null && inventoryLimit > 0)
              'inventoryLimit': inventoryLimit,
            'isActive': isActive,
          },
          decoder: TransferProductModel.fromJson,
        );
  }

  Future<TransferProductModel> patchAdminTransferProduct({
    required String token,
    required String productId,
    int? priceCents,
    Map<String, dynamic>? info,
    int? inventoryLimit,
    bool? isActive,
  }) {
    return _ref.read(apiClientProvider).patch<TransferProductModel>(
          '/admin/products/transfers/$productId',
          token: token,
          body: <String, dynamic>{
            if (priceCents != null) 'priceCents': priceCents,
            if (info != null) 'info': info,
            if (inventoryLimit != null) 'inventoryLimit': inventoryLimit,
            if (isActive != null) 'isActive': isActive,
          },
          decoder: TransferProductModel.fromJson,
        );
  }

  Future<void> deleteAdminTransferProduct({
    required String token,
    required String productId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          '/admin/products/transfers/$productId',
          token: token,
          decoder: (_) {},
        );
  }

  Future<List<PromoCodeViewModel>> listAdminPromoCodes({
    required String token,
    int? eventId,
    bool? active,
  }) {
    return _ref.read(apiClientProvider).get<List<PromoCodeViewModel>>(
      '/admin/promo-codes',
      token: token,
      query: <String, dynamic>{
        if (eventId != null && eventId > 0) 'event_id': eventId,
        if (active != null) 'active': active,
      },
      decoder: (data) {
        final map = asMap(data);
        return asList(map['items']).map(PromoCodeViewModel.fromJson).toList();
      },
    );
  }

  Future<PromoCodeViewModel> createAdminPromoCode({
    required String token,
    required String code,
    required String discountType,
    required int value,
    int? usageLimit,
    String? activeFrom,
    String? activeTo,
    int? eventId,
    bool isActive = true,
  }) {
    return _ref.read(apiClientProvider).post<PromoCodeViewModel>(
          '/admin/promo-codes',
          token: token,
          body: <String, dynamic>{
            'code': code.trim().toUpperCase(),
            'discountType': discountType.toUpperCase(),
            'value': value,
            if (usageLimit != null && usageLimit > 0) 'usageLimit': usageLimit,
            if ((activeFrom ?? '').trim().isNotEmpty) 'activeFrom': activeFrom,
            if ((activeTo ?? '').trim().isNotEmpty) 'activeTo': activeTo,
            if (eventId != null && eventId > 0) 'eventId': eventId,
            'isActive': isActive,
          },
          decoder: PromoCodeViewModel.fromJson,
        );
  }

  Future<PromoCodeViewModel> patchAdminPromoCode({
    required String token,
    required String promoId,
    String? discountType,
    int? value,
    int? usageLimit,
    String? activeFrom,
    String? activeTo,
    int? eventId,
    bool? isActive,
  }) {
    return _ref.read(apiClientProvider).patch<PromoCodeViewModel>(
          '/admin/promo-codes/$promoId',
          token: token,
          body: <String, dynamic>{
            if ((discountType ?? '').trim().isNotEmpty)
              'discountType': discountType!.toUpperCase(),
            if (value != null) 'value': value,
            if (usageLimit != null) 'usageLimit': usageLimit,
            if ((activeFrom ?? '').trim().isNotEmpty) 'activeFrom': activeFrom,
            if ((activeTo ?? '').trim().isNotEmpty) 'activeTo': activeTo,
            if (eventId != null) 'eventId': eventId,
            if (isActive != null) 'isActive': isActive,
          },
          decoder: PromoCodeViewModel.fromJson,
        );
  }

  Future<void> deleteAdminPromoCode({
    required String token,
    required String promoId,
  }) {
    return _ref.read(apiClientProvider).delete<void>(
          '/admin/promo-codes/$promoId',
          token: token,
          decoder: (_) {},
        );
  }
}

class PromoCodeViewModel {
  factory PromoCodeViewModel.fromJson(dynamic json) {
    final map = asMap(json);
    return PromoCodeViewModel(
      id: asString(map['id']),
      code: asString(map['code']),
      discountType: asString(map['discountType']).toUpperCase(),
      value: asInt(map['value']),
      usageLimit: map['usageLimit'] == null ? null : asInt(map['usageLimit']),
      usedCount: asInt(map['usedCount']),
      activeFrom: asDateTime(map['activeFrom']),
      activeTo: asDateTime(map['activeTo']),
      eventId: map['eventId'] == null ? null : asInt(map['eventId']),
      isActive: asBool(map['isActive']),
    );
  }
  PromoCodeViewModel({
    required this.id,
    required this.code,
    required this.discountType,
    required this.value,
    required this.usageLimit,
    required this.usedCount,
    required this.activeFrom,
    required this.activeTo,
    required this.eventId,
    required this.isActive,
  });

  final String id;
  final String code;
  final String discountType;
  final int value;
  final int? usageLimit;
  final int usedCount;
  final DateTime? activeFrom;
  final DateTime? activeTo;
  final int? eventId;
  final bool isActive;
}

final ticketingRepositoryProvider =
    Provider<TicketingRepository>((ref) => TicketingRepository(ref));
