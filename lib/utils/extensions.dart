// ignore_for_file: unnecessary_this

extension StringHelpers on String {
  String toIntlPhoneFormat(String countryLongName) {
    if (this == null ||
        this == 'null' || // Excel blank values come through as "null" but
        this.isEmpty ||
        countryLongName == null ||
        countryLongName.isEmpty) {
      return '';
    }

    // This the encoding needed in the Google Places API URL
    // for a '+' sign when denoting international phone #s
    var intlFormatString = '%2B';
    switch (countryLongName?.toLowerCase()) {
      case 'united states':
      case 'british virgin islands':
      case 'turks and caicos islands':
      case 'virgin islands': // US Virgin Islands
        intlFormatString += '1';
        break;
      case 'aruba':
        intlFormatString += '297';
        break;
      case 'mexico':
        intlFormatString += '52';
        break;
      case 'norway':
        intlFormatString += '47';
        break;
      case 'thailand':
        intlFormatString += '66';
        break;
      default:
        intlFormatString += '';
        break;
    }

    // strip out all unwanted characters
    intlFormatString = intlFormatString + replaceAll('(', '');
    intlFormatString = intlFormatString.replaceAll(')', '');
    intlFormatString = intlFormatString.replaceAll(' ', '');
    intlFormatString = intlFormatString.replaceAll('-', '');
    intlFormatString = intlFormatString.replaceAll('+', '');

    return intlFormatString;
  }

  /// Encodes all spaces and commas in a string to safe
  /// character codes for a URL. Spaces get converted to %20
  /// and commas get converted to %2C
  String toURLSafeString() {
    if (this == null ||
        this == 'null' || // Excel blank values come through as "null" but
        this.isEmpty) {
      return '';
    }

    var returnValue = this;
    // Formatted based on these specs:
    // https://developers.google.com/maps/documentation/urls/url-encoding
    // Spaces with %20, a plus sign is also acceptable
    returnValue = returnValue.replaceAll(' ', '%20');
    // Replace commas with %2C
    returnValue = returnValue.replaceAll(',', '%2C');

    return returnValue;
  }

  /// strips URLs of the http:// prefix and also strips
  /// out all other forward slashes with blank
  String stripUrl() {
    var returnValue = this;

    returnValue = returnValue.replaceAll('http://', '');
    returnValue = returnValue.replaceAll('/', '');

    return returnValue;
  }
}
