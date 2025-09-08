package gama.extension.GTFS;

public class TransportRoute {

    private String routeId; // Route identifier
    private String shortName; // Short name of the route
    private String longName; // Long name of the route
    private int type; // Type of transport (e.g., bus, tram, etc.)

    // Constructor
    public TransportRoute(String routeId, String shortName, String longName, int type) {
        this.routeId = routeId;
        this.shortName = shortName;
        this.longName = longName;
        this.type = type;
    }

    // Getters and Setters
    public String getRouteId() {
        return routeId;
    }

    public void setRouteId(String routeId) {
        this.routeId = routeId;
    }

    public String getShortName() {
        return shortName;
    }

    public void setShortName(String shortName) {
        this.shortName = shortName;
    }

    public String getLongName() {
        return longName;
    }

    public void setLongName(String longName) {
        this.longName = longName;
    }

    public int getType() {
        return type;
    }

    public void setType(int type) {
        this.type = type;
    }

    // Method to display route information
    @Override
    public String toString() {
        return "Route ID: " + routeId + ", Short Name: " + shortName + ", Long Name: " + longName + ", Type: " + type;
    }

}
