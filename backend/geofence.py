import math


def haversine_distance(lat1, lon1, lat2, lon2):
    """
    Calculate distance between two GPS coordinates
    using the Haversine formula.

    Returns:
        Distance in meters.
    """

    R = 6371000  # Earth radius in meters

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

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


def check_geofence(
    latitude,
    longitude,
    allowed_latitude,
    allowed_longitude,
    allowed_radius
):
    """
    Check whether a GPS coordinate is inside
    the allowed geofence radius.

    Returns:
        True  -> inside geofence
        False -> outside geofence
    """

    distance = haversine_distance(
        latitude,
        longitude,
        allowed_latitude,
        allowed_longitude
    )

    return distance <= allowed_radius