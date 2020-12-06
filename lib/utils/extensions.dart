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
        intlFormatString += '1';
        break;
      case 'aruba':
        intlFormatString += '297';
        break;
      case 'british virgin islands':
        intlFormatString += '1-284';
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
      case 'turks and caicos islands':
        intlFormatString += '1-649';
        break;
      case 'virgin islands': // US Virgin Islands
        intlFormatString += '1-340';
        break;
      default:
        intlFormatString += '1';
        break;
    }

    intlFormatString = intlFormatString + replaceAll('(', '');
    intlFormatString = intlFormatString.replaceAll(')', '');
    intlFormatString = intlFormatString.replaceAll(' ', '');
    intlFormatString = intlFormatString.replaceAll('-', '');

    // strip out all possible characters
    return intlFormatString;
  }

  String toURLSafeString() => replaceAll(' ', '%20');
}
