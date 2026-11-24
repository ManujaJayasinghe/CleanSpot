/// Centre point of each Regional Director of Health Services (RDHS) area in
/// the dengue data, used to put a CleanSpot report on the map into a district.
///
/// Each point is the coordinate of the RDHS's main town, taken from the
/// Wikipedia/Wikidata coordinates of that town and rounded to four decimals.
/// Kalmunai is its own RDHS in the dengue reports, so it has its own centre.
///
/// IMPORTANT: this is an APPROXIMATION. A report is assigned to the district
/// whose centre is nearest in a straight line. RDHS areas are not circles
/// around a town, so a report near a boundary can land in the neighbouring
/// district, and the Ampara/Kalmunai split in particular is rough.
class DistrictCentre {
  const DistrictCentre(this.name, this.lat, this.lng);

  /// Name exactly as in the dengue CSV.
  final String name;
  final double lat;
  final double lng;
}

const List<DistrictCentre> districtCentres = [
  DistrictCentre('Colombo', 6.9344, 79.8428),
  DistrictCentre('Gampaha', 7.0917, 79.9997),
  DistrictCentre('Kalutara', 6.5869, 79.9603),
  DistrictCentre('Kandy', 7.2931, 80.6350),
  DistrictCentre('Matale', 7.4667, 80.6167),
  DistrictCentre('Nuwara Eliya', 6.9667, 80.7667),
  DistrictCentre('Galle', 6.0328, 80.2156),
  DistrictCentre('Hambantota', 6.1244, 81.1225),
  DistrictCentre('Matara', 5.9500, 80.5333),
  DistrictCentre('Jaffna', 9.6647, 80.0167),
  DistrictCentre('Kilinochchi', 9.3833, 80.4086),
  DistrictCentre('Mannar', 8.9667, 79.8833),
  DistrictCentre('Vavuniya', 8.7500, 80.4833),
  DistrictCentre('Mullaitivu', 9.2833, 80.8000),
  DistrictCentre('Batticaloa', 7.7167, 81.7000),
  DistrictCentre('Ampara', 7.2833, 81.6667),
  DistrictCentre('Trincomalee', 8.5667, 81.2333),
  DistrictCentre('Kalmunai', 7.4167, 81.8167),
  DistrictCentre('Kurunegala', 7.4833, 80.3667),
  DistrictCentre('Puttalam', 8.0342, 79.8353),
  DistrictCentre('Anuradhapura', 8.3350, 80.4108),
  DistrictCentre('Polonnaruwa', 7.9333, 81.0000),
  DistrictCentre('Badulla', 6.9847, 81.0564),
  DistrictCentre('Moneragala', 6.8714, 81.3486),
  DistrictCentre('Ratnapura', 6.6806, 80.4022),
  DistrictCentre('Kegalle', 7.2531, 80.3453),
];
