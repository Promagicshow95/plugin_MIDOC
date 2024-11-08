package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;

public class TransportStop {
    private String stopId;
    private String stopName;
    private GamaPoint location; // Using GamaPoint to handle location

    // Constructor
    public TransportStop(String stopId, String stopName, double stopLat, double stopLon) {
        this.stopId = stopId;
        this.stopName = stopName;
        this.location = new GamaPoint(stopLat, stopLon);
    }
    
    public double getLatitude() {
        return location.getY();  // GamaPoint.getY() returns the latitude (y)
    }

    // Method to get the longitude (x)
    public double getLongitude() {
        return location.getX();  // GamaPoint.getX() returns the longitude (x)
    }

    // Getters
    public String getStopId() {
        return stopId;
    }

    public String getStopName() {
        return stopName;
    }

    public GamaPoint getLocation() {
        return location;
    }
}
