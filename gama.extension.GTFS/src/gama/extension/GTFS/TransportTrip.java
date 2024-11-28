package gama.extension.GTFS;

import gama.core.util.GamaListFactory;
import gama.core.util.GamaMapFactory;
import gama.core.util.IList;
import gama.core.util.IMap;
import gama.gaml.types.Types;

public class TransportTrip {

    private String routeId; // Route identifier
    private String serviceId; // Service identifier
    private int tripId; // Trip identifier
    private int directionId; // Direction identifier
    private int shapeId; // Shape identifier
    private TransportRoute transportRoute; // The route associated with this trip
    private IMap<Integer, TransportStop> stopSequenceMap; // Sequence -> Stop

    // Constructor
    @SuppressWarnings("unchecked")
	public TransportTrip(String routeId, String serviceId, int tripId, int directionId, int shapeId, TransportRoute transportRoute) {
        this.routeId = routeId;
        this.serviceId = serviceId;
        this.tripId = tripId;
        this.directionId = directionId;
        this.shapeId = shapeId;
        this.transportRoute = transportRoute;
        this.stopSequenceMap = GamaMapFactory.create(Types.INT, Types.get(TransportStop.class));
    }

    // Add a stop to the trip with its sequence
    public void addStopToSequence(int sequence, TransportStop stop) {
        stopSequenceMap.put(sequence, stop);
    }

    // Get the stop for a given sequence
    public TransportStop getStopBySequence(int sequence) {
        return stopSequenceMap.get(sequence);
    }

    // Get all stops in sequence order
    public IList<TransportStop> getStopsInOrder() {
        IList<TransportStop> orderedStops = GamaListFactory.create();
        stopSequenceMap.keySet().stream()
            .sorted()
            .forEach(sequence -> orderedStops.add(stopSequenceMap.get(sequence)));
        return orderedStops;
    }

    // Get the predecessors of a given stop in the trip
    public IList<TransportStop> getPredecessors(int sequence) {
        IList<TransportStop> predecessors = GamaListFactory.create();
        stopSequenceMap.keySet().stream()
            .filter(seq -> seq < sequence)
            .sorted()
            .forEach(seq -> predecessors.add(stopSequenceMap.get(seq)));
        return predecessors;
    }

    // Get the last stop (destination) in the trip
    public TransportStop getDestination() {
        if (stopSequenceMap.isEmpty()) {
            return null;
        }
        int lastSequence = stopSequenceMap.keySet().stream().max(Integer::compare).orElse(-1);
        return stopSequenceMap.get(lastSequence);
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

    // Method to display trip information
    @Override
    public String toString() {
        return "Trip ID: " + tripId + ", Route ID: " + routeId + ", Stops: " + stopSequenceMap.size() + " stops.";
    }
}
