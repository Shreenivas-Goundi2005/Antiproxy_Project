import math


# ============================================================
# ANTIPROXY GEOFENCE SETTINGS
# ============================================================

CAMPUS_LATITUDE = 16.1733789
CAMPUS_LONGITUDE = 75.6581422

# Allowed distance from campus center in meters
ALLOWED_RADIUS = 500


# ============================================================
# CALCULATE GPS DISTANCE
# ============================================================

def calculate_distance(lat1, lon1, lat2, lon2):
    """
    Calculate distance between two GPS coordinates in meters
    using the Haversine formula.
    """

    earth_radius = 6371000  # meters

    # Convert degrees to radians
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)

    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1_rad)
        * math.cos(lat2_rad)
        * math.sin(delta_lon / 2) ** 2
    )

    c = 2 * math.atan2(
        math.sqrt(a),
        math.sqrt(1 - a)
    )

    return earth_radius * c


# ============================================================
# CHECK GEOFENCE
# ============================================================

def check_geofence(latitude, longitude):
    """
    Check whether the current student location
    is inside the allowed campus area.
    """

    distance = calculate_distance(
        CAMPUS_LATITUDE,
        CAMPUS_LONGITUDE,
        latitude,
        longitude
    )

    inside = distance <= ALLOWED_RADIUS

    return {
        "inside": inside,
        "distance": round(distance, 2),
        "allowed_radius": ALLOWED_RADIUS
    }


# ============================================================
# TEST
# ============================================================

if __name__ == "__main__":

    print("======================================")
    print("AntiProxy Geofence Test")
    print("======================================")

    print(
        "Campus latitude:",
        CAMPUS_LATITUDE
    )

    print(
        "Campus longitude:",
        CAMPUS_LONGITUDE
    )

    print(
        "Allowed radius:",
        ALLOWED_RADIUS,
        "meters"
    )

    # Test using exact campus coordinates
    result = check_geofence(
        CAMPUS_LATITUDE,
        CAMPUS_LONGITUDE
    )

    print()
    print("Test result:")
    print(result)

    if result["inside"]:
        print("GEOFENCE: PASS")
    else:
        print("GEOFENCE: FAIL")