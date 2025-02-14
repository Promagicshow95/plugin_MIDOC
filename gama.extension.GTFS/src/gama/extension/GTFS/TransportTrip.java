package gama.extension.GTFS;

import java.util.Map;

import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;

public class TransportTrip {

    private String routeId; 
    private String serviceId; 
    private int tripId;
    private int directionId; 
    private int shapeId;
    private IList<String> stopIdsInOrder; 
    private IList<IMap<String, Object>> stopDetails; 

    // Constructor
    public TransportTrip(String routeId, String serviceId, int tripId, int directionId, int shapeId) {
        this.routeId = routeId;
        this.serviceId = serviceId;
        this.tripId = tripId;
        this.directionId = directionId;
        this.shapeId = shapeId;
        this.stopIdsInOrder = GamaListFactory.create(); // Initialize list
        this.stopDetails = GamaListFactory.create();    // Initialize stop details
    }

    // Add a stop_id in sequence order
    public void addStop(String stopId) {
        stopIdsInOrder.add(stopId);
    }

    // Add stop details (stopId and departureTime)
    public void addStopDetail(String stopId, String departureTime) {
        IMap<String, Object> stopEntry = GamaMapFactory.create();
        stopEntry.put("stopId", stopId);
        stopEntry.put("departureTime", departureTime);
        stopDetails.add(stopEntry);
    }

    // Set stop details
    public void setStopDetails(IList<IMap<String, Object>> stopDetails) {
        this.stopDetails = stopDetails;
    }

    // Get stop details
    public IList<IMap<String, Object>> getStopDetails() {
        return stopDetails;
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
    
    /**
     * Returns a list of TransportStop objects corresponding to the stop IDs in this trip.
     * 
     * @param stopsMap A map containing stop IDs and their corresponding TransportStop objects.
     * @return A list of TransportStop objects.
     */
    public IList<TransportStop> getStops(Map<String, TransportStop> stopsMap) {
        IList<TransportStop> stops = GamaListFactory.create();
        for (String stopId : stopIdsInOrder) {
            TransportStop stop = stopsMap.get(stopId);
            if (stop != null) {
                stops.add(stop);
            } else {
                System.err.println("[Warning] Stop ID not found in stopsMap: " + stopId);
            }
        }
        return stops;
    }

    // Display trip information
    @Override
    public String toString() {
        return "Trip ID: " + tripId + ", Route ID: " + routeId + ", Stops: " + stopIdsInOrder.size() + " stops.";
    }
}
