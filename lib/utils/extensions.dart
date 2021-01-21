// ignore_for_file: unnecessary_this

import 'package:us_states/us_states.dart';

extension StringHelpers on String {
  String toStateAbbreviation() {
    if (this.length == 2) {
      // denotes it is already abbreviated
      return this;
    }

    final stateAbbreviation = USStates.getAbbreviation(this);

    if (stateAbbreviation.isNotEmpty) {
      return stateAbbreviation;
    }

    return this;
  }

  String toExpandAbbreviations() {
    if (this == null) {
      return this;
    }

    var returnValue = this.toLowerCase();

    // TODO: CHANGE TO REGULAR EXPRESSION - LOOK FOR ABBREVIATION FOLLOWED BY SPACE, PERIOD OR COMMA
    // TODO: BREAK UP THE GOOGLE ADDRESS INTO CHUNKS IF POSSIBLE SO WE CAN REVERSE COMPARE TO JUST STREET OF AVTOPIA DATA.

    returnValue = returnValue.replaceAll(' rd', ' road');
    returnValue = returnValue.replaceAll(' rd.', ' road');
    returnValue = returnValue.replaceAll(' dr', ' drive');
    returnValue = returnValue.replaceAll(' dr.', ' drive');
    returnValue = returnValue.replaceAll(' st', ' street');
    returnValue = returnValue.replaceAll(' st.', ' street');
    returnValue = returnValue.replaceAll(' str', ' street');
    returnValue = returnValue.replaceAll(' str.', ' street');
    returnValue = returnValue.replaceAll(' ft', ' fort');
    returnValue = returnValue.replaceAll(' ft.', ' fort');
    returnValue = returnValue.replaceAll(' ave', ' avenue');
    returnValue = returnValue.replaceAll(' ave.', ' avenue');
    returnValue = returnValue.replaceAll(' ln', ' lane');
    returnValue = returnValue.replaceAll(' hwy', ' highway');
    returnValue = returnValue.replaceAll(' blvd', ' boulevard');
    returnValue = returnValue.replaceAll(' bldg', ' building');
    returnValue = returnValue.replaceAll(' pl', ' place');
    returnValue = returnValue.replaceAll(' pky', ' parkway');
    returnValue = returnValue.replaceAll(' pkwy', ' parkway');
    returnValue = returnValue.replaceAll(' expy', ' expressway');
    returnValue = returnValue.replaceAll(' ter', ' terrace');
    returnValue = returnValue.replaceAll(' tpke', ' turnpike');
    returnValue = returnValue.replaceAll(' ste', ' suite');
    returnValue = returnValue.replaceAll(' cir', ' circle');
    returnValue = returnValue.replaceAll(' ct', ' court');
    returnValue = returnValue.replaceAll(' ctr', ' center');
    returnValue = returnValue.replaceAll(' apt', ' apartment');
    returnValue = returnValue.replaceAll(' is', ' island');
    returnValue = returnValue.replaceAll(' jct', ' junction');
    returnValue = returnValue.replaceAll(' e ', ' east');
    returnValue = returnValue.replaceAll(' n ', ' north');
    returnValue = returnValue.replaceAll(' s ', ' south');
    returnValue = returnValue.replaceAll(' w ', ' west');
    returnValue = returnValue.replaceAll(' nw ', ' northwest');
    returnValue = returnValue.replaceAll(' ne ', ' northeast');
    returnValue = returnValue.replaceAll(' se ', ' southeast');
    returnValue = returnValue.replaceAll(' sw ', ' southwest');
    returnValue = returnValue.replaceAll(' e. ', ' east');
    returnValue = returnValue.replaceAll(' n. ', ' north');
    returnValue = returnValue.replaceAll(' s. ', ' south');
    returnValue = returnValue.replaceAll(' w. ', ' west');
    returnValue = returnValue.replaceAll(' nw. ', ' northwest');
    returnValue = returnValue.replaceAll(' ne. ', ' northeast');
    returnValue = returnValue.replaceAll(' se. ', ' southeast');
    returnValue = returnValue.replaceAll(' sw. ', ' southwest');

    print('REPLACED $this WITH $returnValue');

    return returnValue;
  }

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
