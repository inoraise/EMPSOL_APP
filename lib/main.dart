import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For JSON decoding
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart'; // For geolocation

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('EMPSOLGL')),
        body: JsonDataGrid(),
      ),
    );
  }
}

class JsonDataGrid extends StatefulWidget {
  @override
  _JsonDataGridState createState() => _JsonDataGridState();
}

class _JsonDataGridState extends State<JsonDataGrid> {
  String _location = "Location not fetched";
  List<dynamic> _data = [];
  List<dynamic> _filteredData = []; // New list for filtered data
  TextEditingController _searchController =
      TextEditingController(); // Search controller

  @override
  void initState() {
    super.initState();
    _fetchDataFromApi();
    // Add listener to the search controller to filter data
    _searchController.addListener(() {
      filterData();
    });
  }

// Function to filter data based on the search query
  void filterData() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredData = _data.where((item) {
        return item['FileNo'].toLowerCase().contains(query) ||
            item['CustomerName'].toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _fetchDataFromApi() async {
    try {
      // Replace this with your API endpoint
      final response = await http
          .get(Uri.parse('https://empyrealsolar.in/APIs/GeoOperations.php'));
      if (response.statusCode == 200) {
        Map<String, dynamic> jsonData = json.decode(response.body);
        // Check if 'success' is true and if 'data' exists
        if (jsonData['success'] == true && jsonData['data'] != null) {
          // Assign the 'data' array to the _data list
          setState(() {
            _data = jsonData['data']; // Update the data
          });
        }
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  Future<void> requestLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isDenied) {
      await Permission.location.request();
    }
  }

  Future<void> _editRow(int rowIndex) async {
    // Fetch the current row data based on the index
    var currentRowData = _filteredData[rowIndex];

    // Create text controllers for the dialog inputs
    TextEditingController fileNoController =
        TextEditingController(text: currentRowData['FileNo']);
    TextEditingController customerNameController =
        TextEditingController(text: currentRowData['CustomerName']);
    TextEditingController latitudeController =
        TextEditingController(text: currentRowData['Latitude'].toString());
    TextEditingController longitudeController =
        TextEditingController(text: currentRowData['Longitude'].toString());

    // Show dialog to edit the row
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Update Geo Location"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fileNoController,
                decoration: InputDecoration(labelText: 'FileNo'),
                readOnly: true, // Disable editing
              ),
              TextField(
                controller: customerNameController,
                decoration: InputDecoration(labelText: 'Customer Name'),
                readOnly: true, // Disable editing
              ),
              TextField(
                controller: latitudeController,
                decoration: InputDecoration(labelText: 'Latitude'),
                readOnly: true, // Disable editing
              ),
              TextField(
                controller: longitudeController,
                decoration: InputDecoration(labelText: 'Longitude'),
                readOnly: true, // Disable editing
              ),
              ElevatedButton(
                onPressed: () async {
                  // Fetch current location
                  Position position = await _getCurrentLocation();
                  // Update text fields with the fetched location
                  latitudeController.text = position.latitude.toString();
                  longitudeController.text = position.longitude.toString();
                },
                child: const Text("Get Current Location"),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                // Close the dialog
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                // Prepare the JSON body for the API call
                var updatedData = {
                  'FileNo': fileNoController.text,
                  'Latitude': double.tryParse(latitudeController.text) ?? 0.0,
                  'Longitude': double.tryParse(longitudeController.text) ?? 0.0,
                };

                // Call the update API
                var response = await _updateLocation(rowIndex, updatedData);

                // Check the response
                if (response.statusCode == 200) {
                  // Optionally, update the local state with new values if needed
                  setState(() {
                    _filteredData[rowIndex]['Latitude'] =
                        updatedData['Latitude'];
                    _filteredData[rowIndex]['Longitude'] =
                        updatedData['Longitude'];
                  });
                  // Show success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Location updated successfully!")),
                  );
                } else {
                  // Handle error (optional)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to update location.")),
                  );
                }

                // Close the dialog
                Navigator.of(context).pop();
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

// Function to get the current location
  Future<Position> _getCurrentLocation() async {
    // Check for location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Handle the case when permission is denied
        throw Exception('Location permission denied');
      }
    }

    // Check if permission is granted
    if (permission == LocationPermission.deniedForever) {
      // Handle the case when permission is permanently denied
      throw Exception(
          'Location permission permanently denied. Please enable it in settings.');
    }

    // Get current location with high accuracy
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      return position;
    } catch (e) {
      // Handle exceptions related to getting the current position
      throw Exception('Failed to get location: $e');
    }
  }

// Function to call the update API
  Future<http.Response> _updateLocation(
      int rowIndex, Map<String, dynamic> updatedData) async {
    final String apiUrl =
        'https://empyrealsolar.in/APIs/GeoOperations.php'; // Replace with your API URL

    // Create the request body
    String jsonBody = json.encode({
      'action': 'update', // Assuming each item has an 'id'
      ...updatedData,
    });

    print(jsonBody);

    return await http.post(
      Uri.parse(apiUrl),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonBody,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _filteredData.isEmpty
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const <DataColumn>[
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('FileNo')),
                        DataColumn(label: Text('Customer Name')),
                        DataColumn(label: Text('Latitude')),
                        DataColumn(label: Text('Longitude')),
                      ],
                      rows: List<DataRow>.generate(
                        _filteredData.length,
                        (index) {
                          var item = _filteredData[index];
                          bool hasCoordinates =
                              item['Latitude'] != "0.00000000" ||
                                  item['Longitude'] != "0.00000000";

                          return DataRow(
                            color: hasCoordinates
                                ? MaterialStateProperty.all(Colors.green[100])
                                : null,
                            cells: <DataCell>[
                              DataCell(
                                GestureDetector(
                                  onDoubleTap: () {
                                    _editRow(
                                        index); // Call your edit function with the correct index
                                  },
                                  child: Text(item['id'].toString()),
                                ),
                              ),
                              DataCell(
                                GestureDetector(
                                  onDoubleTap: () {
                                    _editRow(index);
                                  },
                                  child: Text(item['FileNo']),
                                ),
                              ),
                              DataCell(
                                GestureDetector(
                                  onDoubleTap: () {
                                    _editRow(index);
                                  },
                                  child: Text(item['CustomerName']),
                                ),
                              ),
                              DataCell(
                                GestureDetector(
                                  onDoubleTap: () {
                                    _editRow(index);
                                  },
                                  child: Text(item['Latitude'].toString()),
                                ),
                              ),
                              DataCell(
                                GestureDetector(
                                  onDoubleTap: () {
                                    _editRow(index);
                                  },
                                  child: Text(item['Longitude'].toString()),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});

//   final String title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

// class _MyHomePageState extends State<MyHomePage> {
//   List<dynamic> _data = []; // Holds the API data
//   bool _loading = true; // To track the loading state

//   List<List<String>> _gridData = [];
//   String _location = "Location not fetched";

//   @override
//   void initState() {
//     super.initState();
//     requestStoragePermission();
//   }

//   // Function to fetch data from the API
//   Future<void> _fetchDataFromApi() async {
//     try {
//       // Replace this with your API endpoint
//       final response = await http
//           .get(Uri.parse('https://empyrealsolar.in/APIs/GeoOperations.php'));
//       if (response.statusCode == 200) {
//         Map<String, dynamic> jsonData = json.decode(response.body);
//         // Check if 'success' is true and if 'data' exists
//         if (jsonData['success'] == true && jsonData['data'] != null) {
//           // Assign the 'data' array to the _data list
//           _data = jsonData['data'];
//           _loading = false;
//         }
//       } else {
//         throw Exception('Failed to load data');
//       }
//     } catch (e) {
//       setState(() {
//         _loading = false;
//       });
//       print('Error fetching data: $e');
//     }
//   }

//   // Request storage permissions
//   Future<void> requestStoragePermission() async {
//     await _fetchDataFromApi();
//     var status = await Permission.storage.status;
//     if (status.isDenied) {
//       await Permission.storage.request();
//     }
//   }

//   // Request location permissions
//   Future<void> requestLocationPermission() async {
//     var status = await Permission.location.status;
//     if (status.isDenied) {
//       await Permission.location.request();
//     }
//   }

//   // Function to open a popup for editing a row
//   bool _isLoading = false; // Loading state
//   Future<void> _editRow(int rowIndex) async {
//     List<String> currentRowData = _gridData[rowIndex];
//     _location = "Location not fetched";
//     // Show dialog to edit the row and fetch location
//     final updatedRowData = await showDialog<List<String>>(
//       context: context,
//       builder: (BuildContext context) {
//         List<TextEditingController> controllers = [];
//         for (var data in currentRowData) {
//           controllers.add(TextEditingController(text: data));
//         }
//         if (_isLoading) {
//           return Loader();
//         }
//         return StatefulBuilder(
//           builder: (BuildContext context, StateSetter setState) {
//             return AlertDialog(
//               title: const Text("Update Project Location"),
//               content: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   ...List.generate(currentRowData.length, (index) {
//                     String labelText =
//                         _gridData[0][index]; // Fallback if not the first row
//                     return TextField(
//                       controller: controllers[index],
//                       decoration: InputDecoration(labelText: labelText),
//                       readOnly: true,
//                     );
//                   }),
//                   const SizedBox(height: 20),
//                   Text(_location),
//                   ElevatedButton(
//                     onPressed: () async {
//                       setState(() {
//                         _isLoading = true; // Start loading
//                       });
//                       // Fetch current location when button is clicked
//                       await requestLocationPermission();
//                       Position position = await Geolocator.getCurrentPosition(
//                           desiredAccuracy: LocationAccuracy.high);
//                       // Set the values in the respective text fields
//                       controllers[controllers.length - 2].text =
//                           position.latitude.toString(); // Last but one
//                       controllers[controllers.length - 1].text =
//                           position.longitude.toString(); // Last one
//                       setState(() {
//                         _location =
//                             "Lat: ${position.latitude}, Lon: ${position.longitude}";
//                         _isLoading = false; // End loading
//                       });
//                     },
//                     child: const Text("Get Current Location"),
//                   ),
//                 ],
//               ),
//               actions: <Widget>[
//                 TextButton(
//                   onPressed: () {
//                     Navigator.of(context).pop(null);
//                   },
//                   child: const Text("Cancel"),
//                 ),
//                 TextButton(
//                   onPressed: () {
//                     List<String> editedRow =
//                         controllers.map((c) => c.text).toList();
//                     Navigator.of(context).pop(editedRow);
//                   },
//                   child: const Text("Save"),
//                 ),
//               ],
//             );
//           },
//         );
//       },
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return _data.isEmpty
//         ? Center(
//             child:
//                 CircularProgressIndicator()) // Show a loader if the data is not yet available
//         : SingleChildScrollView(
//             scrollDirection: Axis.vertical,
//             child: DataTable(
//               columns: const <DataColumn>[
//                 DataColumn(label: Text('ID')),
//                 DataColumn(label: Text('FileNo')),
//                 DataColumn(label: Text('Customer Name')),
//                 DataColumn(label: Text('Latitude')),
//                 DataColumn(label: Text('Longitude')),
//               ],
//               rows: _data.map<DataRow>((item) {
//                 return DataRow(
//                   cells: <DataCell>[
//                     DataCell(Text(item['id'].toString())),
//                     DataCell(Text(item['FileNo'])),
//                     DataCell(Text(item['CustomerName'])),
//                     DataCell(Text(item['Latitude'].toString())),
//                     DataCell(Text(item['Longitude'].toString())),
//                   ],
//                 );
//               }).toList(),
//             ),
//           );
//   }
// }
