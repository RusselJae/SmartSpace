/// Application settings model for managing configurable values
/// 
/// This model stores all settings that should be manageable through the admin panel
/// instead of being hardcoded in the application.
class AppSettings {
  const AppSettings({
    // Payment Settings
    this.gcashAccountNumber = '09123456789',
    this.gcashAccountName = 'Rosalie M. Enon',
    this.qrCodeImagePath = 'assets/images/qrcode.jpg',
    this.codDownpaymentPercentage = 20.0,
    this.paymentConfirmationTimeMinutes = 15,
    
    // Shipping Settings
    this.freeShippingProductCount = 3,
    this.freeShippingCities = const ['dasmariñas', 'dasmarinas'],
    this.specialShippingCities = const <String, double>{
      'bacoor': 1800.0,
    },
    this.defaultShippingFeeBase = 3000.0,
    this.defaultShippingFeeMax = 5000.0,

    // Installment / lay-away policy + schedule
    this.layawayDownpaymentMin = 3000.0,
    this.layawayDownpaymentMax = 5000.0,
    this.huluganDownpaymentPercent = 40.0,
    this.huluganInterestPercent = 6.0,
    this.installmentTermMonths = 3,
    this.lateFeePerDay = 100.0,
    
    // Store Information
    this.storeName = 'Wood Home Furniture Trading',
    this.storeEmail = '',
    this.storePhone = '',
    this.storeAddress = '',
    this.logoImagePath = 'assets/images/logo.jpg',
    
    // Tax and Fees
    this.taxRate = 0.0,
    this.serviceFee = 0.0,
    
    // Other Settings
    this.minOrderAmount = 0.0,
    this.maxOrderAmount = 0.0,
    this.orderCancellationTimeMinutes = 60,
  });

  // Payment Settings
  final String gcashAccountNumber;
  final String gcashAccountName;
  final String qrCodeImagePath;
  final double codDownpaymentPercentage; // Percentage (e.g., 20.0 for 20%)
  final int paymentConfirmationTimeMinutes;

  // Shipping Settings
  final int freeShippingProductCount; // Free shipping if user buys this many products
  final List<String> freeShippingCities; // Cities with free shipping
  final Map<String, double> specialShippingCities; // City name -> shipping fee
  final double defaultShippingFeeBase; // Base shipping fee for other locations
  final double defaultShippingFeeMax; // Maximum shipping fee for other locations

  // Installment / lay-away policy + schedule
  final double layawayDownpaymentMin;
  final double layawayDownpaymentMax;
  final double huluganDownpaymentPercent;
  final double huluganInterestPercent;
  final int installmentTermMonths;
  final double lateFeePerDay;

  // Store Information
  final String storeName;
  final String storeEmail;
  final String storePhone;
  final String storeAddress;
  final String logoImagePath;

  // Tax and Fees
  final double taxRate; // Tax rate as percentage (e.g., 12.0 for 12%)
  final double serviceFee; // Service fee amount

  // Other Settings
  final double minOrderAmount; // Minimum order amount (0 = no minimum)
  final double maxOrderAmount; // Maximum order amount (0 = no maximum)
  final int orderCancellationTimeMinutes; // Time before order can be cancelled

  AppSettings copyWith({
    String? gcashAccountNumber,
    String? gcashAccountName,
    String? qrCodeImagePath,
    double? codDownpaymentPercentage,
    int? paymentConfirmationTimeMinutes,
    int? freeShippingProductCount,
    List<String>? freeShippingCities,
    Map<String, double>? specialShippingCities,
    double? defaultShippingFeeBase,
    double? defaultShippingFeeMax,
    double? layawayDownpaymentMin,
    double? layawayDownpaymentMax,
    double? huluganDownpaymentPercent,
    double? huluganInterestPercent,
    int? installmentTermMonths,
    double? lateFeePerDay,
    String? storeName,
    String? storeEmail,
    String? storePhone,
    String? storeAddress,
    String? logoImagePath,
    double? taxRate,
    double? serviceFee,
    double? minOrderAmount,
    double? maxOrderAmount,
    int? orderCancellationTimeMinutes,
  }) {
    return AppSettings(
      gcashAccountNumber: gcashAccountNumber ?? this.gcashAccountNumber,
      gcashAccountName: gcashAccountName ?? this.gcashAccountName,
      qrCodeImagePath: qrCodeImagePath ?? this.qrCodeImagePath,
      codDownpaymentPercentage: codDownpaymentPercentage ?? this.codDownpaymentPercentage,
      paymentConfirmationTimeMinutes: paymentConfirmationTimeMinutes ?? this.paymentConfirmationTimeMinutes,
      freeShippingProductCount: freeShippingProductCount ?? this.freeShippingProductCount,
      freeShippingCities: freeShippingCities ?? this.freeShippingCities,
      specialShippingCities: specialShippingCities ?? this.specialShippingCities,
      defaultShippingFeeBase: defaultShippingFeeBase ?? this.defaultShippingFeeBase,
      defaultShippingFeeMax: defaultShippingFeeMax ?? this.defaultShippingFeeMax,
      layawayDownpaymentMin: layawayDownpaymentMin ?? this.layawayDownpaymentMin,
      layawayDownpaymentMax: layawayDownpaymentMax ?? this.layawayDownpaymentMax,
      huluganDownpaymentPercent: huluganDownpaymentPercent ?? this.huluganDownpaymentPercent,
      huluganInterestPercent: huluganInterestPercent ?? this.huluganInterestPercent,
      installmentTermMonths: installmentTermMonths ?? this.installmentTermMonths,
      lateFeePerDay: lateFeePerDay ?? this.lateFeePerDay,
      storeName: storeName ?? this.storeName,
      storeEmail: storeEmail ?? this.storeEmail,
      storePhone: storePhone ?? this.storePhone,
      storeAddress: storeAddress ?? this.storeAddress,
      logoImagePath: logoImagePath ?? this.logoImagePath,
      taxRate: taxRate ?? this.taxRate,
      serviceFee: serviceFee ?? this.serviceFee,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      maxOrderAmount: maxOrderAmount ?? this.maxOrderAmount,
      orderCancellationTimeMinutes: orderCancellationTimeMinutes ?? this.orderCancellationTimeMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gcashAccountNumber': gcashAccountNumber,
      'gcashAccountName': gcashAccountName,
      'qrCodeImagePath': qrCodeImagePath,
      'codDownpaymentPercentage': codDownpaymentPercentage,
      'paymentConfirmationTimeMinutes': paymentConfirmationTimeMinutes,
      'freeShippingProductCount': freeShippingProductCount,
      'freeShippingCities': freeShippingCities,
      'specialShippingCities': specialShippingCities.map((k, v) => MapEntry(k, v)),
      'defaultShippingFeeBase': defaultShippingFeeBase,
      'defaultShippingFeeMax': defaultShippingFeeMax,
      'layawayDownpaymentMin': layawayDownpaymentMin,
      'layawayDownpaymentMax': layawayDownpaymentMax,
      'huluganDownpaymentPercent': huluganDownpaymentPercent,
      'huluganInterestPercent': huluganInterestPercent,
      'installmentTermMonths': installmentTermMonths,
      'lateFeePerDay': lateFeePerDay,
      'storeName': storeName,
      'storeEmail': storeEmail,
      'storePhone': storePhone,
      'storeAddress': storeAddress,
      'logoImagePath': logoImagePath,
      'taxRate': taxRate,
      'serviceFee': serviceFee,
      'minOrderAmount': minOrderAmount,
      'maxOrderAmount': maxOrderAmount,
      'orderCancellationTimeMinutes': orderCancellationTimeMinutes,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      gcashAccountNumber: json['gcashAccountNumber'] as String? ?? '09123456789',
      gcashAccountName: json['gcashAccountName'] as String? ?? 'Rosalie M. Enon',
      qrCodeImagePath: json['qrCodeImagePath'] as String? ?? 'assets/images/qrcode.jpg',
      codDownpaymentPercentage: (json['codDownpaymentPercentage'] as num?)?.toDouble() ?? 20.0,
      paymentConfirmationTimeMinutes: json['paymentConfirmationTimeMinutes'] as int? ?? 15,
      freeShippingProductCount: json['freeShippingProductCount'] as int? ?? 3,
      freeShippingCities: (json['freeShippingCities'] as List?)?.cast<String>() ?? const ['dasmariñas', 'dasmarinas'],
      specialShippingCities: (json['specialShippingCities'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ?? const {'bacoor': 1800.0},
      defaultShippingFeeBase: (json['defaultShippingFeeBase'] as num?)?.toDouble() ?? 3000.0,
      defaultShippingFeeMax: (json['defaultShippingFeeMax'] as num?)?.toDouble() ?? 5000.0,
      layawayDownpaymentMin: (json['layawayDownpaymentMin'] as num?)?.toDouble() ?? 3000.0,
      layawayDownpaymentMax: (json['layawayDownpaymentMax'] as num?)?.toDouble() ?? 5000.0,
      huluganDownpaymentPercent: (json['huluganDownpaymentPercent'] as num?)?.toDouble() ?? 40.0,
      huluganInterestPercent: (json['huluganInterestPercent'] as num?)?.toDouble() ?? 6.0,
      installmentTermMonths: json['installmentTermMonths'] as int? ?? 3,
      lateFeePerDay: (json['lateFeePerDay'] as num?)?.toDouble() ?? 100.0,
      storeName: json['storeName'] as String? ?? 'Wood Home Furniture Trading',
      storeEmail: json['storeEmail'] as String? ?? '',
      storePhone: json['storePhone'] as String? ?? '',
      storeAddress: json['storeAddress'] as String? ?? '',
      logoImagePath: json['logoImagePath'] as String? ?? 'assets/images/logo.jpg',
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] as num?)?.toDouble() ?? 0.0,
      maxOrderAmount: (json['maxOrderAmount'] as num?)?.toDouble() ?? 0.0,
      orderCancellationTimeMinutes: json['orderCancellationTimeMinutes'] as int? ?? 60,
    );
  }
}

