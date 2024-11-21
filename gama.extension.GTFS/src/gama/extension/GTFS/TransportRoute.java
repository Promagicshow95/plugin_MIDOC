package gama.extension.GTFS;

public class TransportRoute {
	
	 private String routeId; // Identifiant de la route
	    private String shortName; // Nom court de la route
	    private String longName; // Nom long de la route
	    private int type; // Type de transport (ex: bus, tramway, etc.)
	  

	    // Constructeur
	    public TransportRoute(String routeId, String shortName, String longName, int type) {
	        this.routeId = routeId;
	        this.shortName = shortName;
	        this.longName = longName;
	        this.type = type;
	        
	    }

	    // Getters et Setters
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

	    // Méthode pour afficher les informations de la route
	    @Override
	    public String toString() {
	        return "Route ID: " + routeId + ", Short Name: " + shortName + ", Long Name: " + longName + ", Type: " + type ;
	    }

}
