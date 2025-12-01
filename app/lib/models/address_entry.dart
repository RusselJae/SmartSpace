class AddressEntry {
  const AddressEntry({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.region,
    required this.postalCode,
    required this.street,
    required this.label,
    required this.isDefault,
  });

  final String id;
  final String fullName;
  final String phoneNumber;
  final String region;
  final String postalCode;
  final String street;
  final String label;
  final bool isDefault;

  AddressEntry copyWith({
    String? id,
    String? fullName,
    String? phoneNumber,
    String? region,
    String? postalCode,
    String? street,
    String? label,
    bool? isDefault,
  }) {
    return AddressEntry(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      street: street ?? this.street,
      label: label ?? this.label,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'region': region,
      'postalCode': postalCode,
      'street': street,
      'label': label,
      'isDefault': isDefault,
    };
  }

  factory AddressEntry.fromJson(Map<String, dynamic> json) {
    return AddressEntry(
      id: json['id'] as String,
      fullName: json['fullName'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      region: json['region'] as String? ?? '',
      postalCode: json['postalCode'] as String? ?? '',
      street: json['street'] as String? ?? '',
      label: json['label'] as String? ?? 'Home',
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

