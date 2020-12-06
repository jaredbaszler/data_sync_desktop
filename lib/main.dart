import 'dart:io';

import 'package:data_sync_desktop/utils/extensions.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

const apiKey = 'AIzaSyAUoR1hu32epmid_r-h7_AiXQWhNu3zr3U';
const originalDataColStart = 0;
const originalDataColEnd = 42;

Data cellByIndex(Sheet writeSheet, int rowIndex, int desiredCellIndex) {
  Data returnCell;

  writeSheet.row(rowIndex).forEach((cell) {
    if (cell.colIndex == desiredCellIndex) {
      returnCell = cell;
    }
  });

  return returnCell;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //runApp(MyApp());

  final data = await rootBundle.load('assets/test_file_2020_11_26.xlsx');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final wbRead = Excel.decodeBytes(bytes);

  final wbWrite = Excel.createExcel();
  final writeSheet = wbWrite.sheets[wbWrite.sheets.keys.first];
  final readSheet = wbRead.sheets[wbRead.sheets.keys.first];

  //print(table); //sheet Name
  //print(excel.tables[table].maxCols);
  //print(excel.tables[table].maxRows);
  //Sheet sheet = excel[table];
  var rowIndex = 0;
  for (final row in readSheet.rows) {
    // Copy this row into the new file
    writeSheet.appendRow(row);

    // Transform the phone number
    //var temp = writeTable.row(i)
    final phoneCell = cellByIndex(writeSheet, rowIndex, Cols.phone);
    final countryCell = cellByIndex(writeSheet, rowIndex, Cols.shipCountry);
    print('row $rowIndex: '
        '${phoneCell.value.toString().toIntlPhoneFormat(countryCell.value)}');
    phoneCell.value =
        phoneCell.value.toString().toIntlPhoneFormat(countryCell.value);

    if (rowIndex == 0) {
      rowIndex++;
      continue;
    } // if header row skip the rest

    //print(row[Cols.accountName]);

    // var tempURL =
    //     basicGoogleFindPlaceByNameURL(businessName: row[Cols.accountName]);
    // print(tempURL);
    // var response = await http.get(
    //     basicGoogleFindPlaceByNameURL(businessName: row[Cols.accountName]));

    // if (response.statusCode == 200) {
    //   var jsonResponse = jsonDecode(response.body);
    //   var itemCount = jsonResponse['totalItems'];
    //   print('Number of businesses returned: $itemCount.');
    //   print(jsonResponse);
    // } else {
    //   print('Request failed with status: ${response.statusCode}.');
    // }

    rowIndex++;

    if (rowIndex > 4) {
      //break; // TODO: turn this on when starting to call API
    } // only do 1 iteration for now
  }

  await wbWrite.encode().then((value) {
    File(join(
        r'C:\Users\jared\source\repos\avtopia\data_sync_desktop\assets\temp.xlsx'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(value);
  });
}

String basicGoogleFindPlaceByNameURL({@required String businessName}) {
  final url =
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json?'
      'input=${businessName.toURLSafeString()}'
      '&api_key=$apiKey'
      '&inputtype=textquery;&fields=business_status,formatted_address,geometry,'
      'icon,name,permanently_closed,photos,place_id,plus_code,types';

  return url;
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}

class Cols {
  static const int id = 0;
  static const int accountName = 1;
  static const int dba1 = 2;
  static const int dba2 = 3;
  static const int dba3 = 4;
  static const int shipStreet1 = 5;
  static const int shipStreet2 = 6;
  static const int shipCity = 7;
  static const int shipState = 8;
  static const int shipZip = 9;
  static const int shipCountry = 10;
  static const int phone = 11;
  static const int website = 12;
  static const int busCat1 = 13;
  static const int busCat2 = 14;
  static const int busCat3 = 15;
  static const int busCat4 = 16;
  static const int busCat5 = 17;
  static const int busCat6 = 18;
  static const int busCat7 = 19;
  static const int busCat8 = 20;
  static const int busCat9 = 21;
  static const int busCat10 = 22;
  static const int tag1 = 23;
  static const int tag2 = 24;
  static const int tag3 = 25;
  static const int tag4 = 26;
  static const int tag5 = 27;
  static const int tag6 = 28;
  static const int tag7 = 29;
  static const int tag8 = 30;
  static const int tag9 = 31;
  static const int tag10 = 32;
  static const int tag11 = 33;
  static const int tag12 = 34;
  static const int tag13 = 35;
  static const int tag14 = 36;
  static const int tag15 = 37;
  static const int tag16 = 38;
  static const int tag17 = 39;
  static const int tag18 = 40;
  static const int tag19 = 41;
  static const int tag20 = 42;
  static const int googleSyncByPhone = 43;
  static const int googleSyncByAddress = 44;
  static const int googleSyncByNameAndAddress = 45;
  static const int googleSyncByNameOnly = 46;
  static const int googleRating = 47;
  static const int googleNumberOfReviews = 48;
  static const int googleWebiste = 49;
  static const int googleCompanyName = 50;
  static const int googleStreet = 51;
  static const int googleStreet2 = 52;
  static const int googleCity = 53;
  static const int googleState = 54;
  static const int googleZip = 55;
  static const int googleCountry = 56;
  static const int googleGPSCoordinates = 57;
  static const int googleImageURL = 58;
}
