package gama.extension.GTFS;

import java.util.List;

public class TransportTrip {

    private String routeId; // Route identifier
    private String serviceId; // Service identifier
    private int tripId; // Trip identifier
    private int directionId; // Direction identifier
    private int shapeId; // Shape identifier
    private TransportRoute transportRoute; // The route associated with this trip
    private List<TransportStop> stops; // List of stops associated with this trip
    private List<String> departureTimes; // List of departure times at each stop

    // Constructor
    public TransportTrip(String routeId, String serviceId, int tripId, int directionId, int shapeId, TransportRoute transportRoute) {
        this.routeId = routeId;
        this.serviceId = serviceId;
        this.tripId = tripId;
        this.directionId = directionId;
        this.shapeId = shapeId;
        this.transportRoute = transportRoute;
    }

    // Getters and Setters
    public String getRouteId() {
        return routeId;
    }

    public void setRouteId(String routeId) {
        this.routeId = routeId;
    }

    public String getServiceId() {
        return serviceId;
    }

    public void setServiceId(String serviceId) {
        this.serviceId = serviceId;
    }

    public int getTripId() {
        return tripId;
    }

    public void setTripId(int tripId) {
        this.tripId = tripId;
    }

    public int getDirectionId() {
        return directionId;
    }

    public void setDirectionId(int directionId) {
        this.directionId = directionId;
    }

    public int getShapeId() {
        return shapeId;
    }

    public void setShapeId(int shapeId) {
        this.shapeId = shapeId;
    }

    public TransportRoute getTransportRoute() {
        return transportRoute;
    }

    public void setTransportRoute(TransportRoute transportRoute) {
        this.transportRoute = transportRoute;
    }

    public List<TransportStop> getStops() {
        return stops;
    }

    public void setStops(List<TransportStop> stops) {
        this.stops = stops;
    }

    public List<String> getDepartureTimes() {
        return departureTimes;
    }

    public void setDepartureTimes(List<String> departureTimes) {
        this.departureTimes = departureTimes;
    }

    // Method to add a stop and its departure time
    public void addStop(String departureTime, TransportStop stop) {
        this.departureTimes.add(departureTime);
        this.stops.add(stop);
    }

    // Method to display trip information
    @Override
    public String toString() {
        return "Trip ID: " + tripId + ", Route ID: " + routeId + ", Stops: " + stops.size() + " stops.";
    }
}
