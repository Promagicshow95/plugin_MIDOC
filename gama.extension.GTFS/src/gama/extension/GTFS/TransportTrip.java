package gama.extension.GTFS;

import java.util.List;

public class TransportTrip {
	
	 private String routeId; // Identifiant de la route
	    private String serviceId; // Identifiant du service
	    private int tripId; // Identifiant du trajet
	    private int directionId; // Direction du trajet
	    private int shapeId; // Identifiant de la forme (shape)
	    private TransportRoute transportRoute; // La route associée à ce trajet
	    private List<TransportStop> stops; // Liste des arrêts associés à ce trajet
	    private List<String> departureTimes; // Liste des heures de départ à chaque arrêt

	    // Constructeur
	    public TransportTrip(String routeId, String serviceId, int tripId, int directionId, int shapeId, TransportRoute transportRoute) {
	        this.routeId = routeId;
	        this.serviceId = serviceId;
	        this.tripId = tripId;
	        this.directionId = directionId;
	        this.shapeId = shapeId;
	        this.transportRoute = transportRoute;
	    }

	    // Getters et Setters
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

	    // Méthode pour ajouter un arrêt et son heure de départ
	    public void addStop(String departureTime, TransportStop stop) {
	        this.departureTimes.add(departureTime);
	        this.stops.add(stop);
	    }

	    // Méthode pour afficher les informations du trajet
	    @Override
	    public String toString() {
	        return "Trip ID: " + tripId + ", Route ID: " + routeId + ", Stops: " + stops.size() + " stops.";
	    }

}
