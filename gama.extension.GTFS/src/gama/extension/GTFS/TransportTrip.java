package gama.extension.GTFS;

import java.util.Map;

import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;

public class TransportTrip {

    private String routeId; 
    private String serviceId; 
    private String tripId;
    private int shapeId;
    private int routeType = -1;
    private IList<String> stopIdsInOrder; 
    private IList<IMap<String, Object>> stopDetails; 

    // Constructor
    public TransportTrip(String routeId, String serviceId, String tripId, int directionId, int shapeId) {
        this.routeId = routeId;
        this.serviceId = serviceId;
        this.tripId = tripId;
        this.shapeId = shapeId;
        this.stopIdsInOrder = GamaListFactory.create(); // Initialize list
        this.stopDetails = GamaListFactory.create();    // Initialize stop details
    }
    
    public int getRouteType() {  
        return routeType;
    }

    public void setRouteType(int routeType) {
        this.routeType = routeType;
    }

    // Add a stop_id in sequence order
    public void addStop(String stopId) {
        stopIdsInOrder.add(stopId);
    }

    // Add stop details (stopId and departureTime)
    public void addStopDetail(String stopId, String departureTime, double shapeDistTraveled) {
        @SuppressWarnings("unchecked")
		IMap<String, Object> stopDetail = GamaMapFactory.create();
        stopDetail.put("stopId", stopId);
        stopDetail.put("departureTime", departureTime);
        stopDetail.put("shapeDistTraveled", shapeDistTraveled); // 🔥 ajoute la distance
        stopDetails.add(stopDetail);
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

	public String getTripId() {
		return tripId;
	}

    public void setTripId(String tripId) {
        this.tripId = tripId;
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
