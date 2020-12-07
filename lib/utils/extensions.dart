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

  String toURLSafeString() => replaceAll(' ', '%20');
}
