package gama.extension.GTFS;

import gama.core.util.GamaListFactory;
import gama.core.util.IList;

public class TransportTrip {

    private String routeId; // Route identifier
    private String serviceId; // Service identifier
    private int tripId; // Trip identifier
    private int directionId; // Direction identifier
    private int shapeId; // Shape identifier
    private IList<String> stopIdsInOrder; // List of stop_ids in sequence

    // Constructor
    public TransportTrip(String routeId, String serviceId, int tripId, int directionId, int shapeId) {
        this.routeId = routeId;
        this.serviceId = serviceId;
        this.tripId = tripId;
        this.directionId = directionId;
        this.shapeId = shapeId;
        this.stopIdsInOrder = GamaListFactory.create(); // Initialize list
    }

    // Add a stop_id in sequence order
    public void addStop(String stopId) {
        stopIdsInOrder.add(stopId);
    }

    // Get stops in order
    public IList<String> getStopsInOrder() {
        return stopIdsInOrder;
    }

    // Get the last stop (destination)
    public String getDestination() {
        return stopIdsInOrder.isEmpty() ? null : stopIdsInOrder.get(stopIdsInOrder.size() - 1);
    }

    // Set the entire list of stop_ids
    public void setStopIdsInOrder(IList<String> stopIdsInOrder) {
        this.stopIdsInOrder = stopIdsInOrder;
    }

    // Getters and Setters for trip attributes
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

    // Display trip information
    @Override
    public String toString() {
        return "Trip ID: " + tripId + ", Route ID: " + routeId + ", Stops: " + stopIdsInOrder.size() + " stops.";
    }
}
