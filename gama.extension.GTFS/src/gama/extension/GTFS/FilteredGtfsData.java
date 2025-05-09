package gama.extension.GTFS;

import java.util.List;

public class FilteredGtfsData {

    private List<TransportStop> stops;
    private List<TransportTrip> trips;
    private List<TransportRoute> routes;
    private List<TransportShape> shapes;

    public List<TransportStop> getStops() {
        return stops;
    }

    public void setStops(List<TransportStop> stops) {
        this.stops = stops;
    }

    public List<TransportTrip> getTrips() {
        return trips;
    }

    public void setTrips(List<TransportTrip> trips) {
        this.trips = trips;
    }

    public List<TransportRoute> getRoutes() {
        return routes;
    }

    public void setRoutes(List<TransportRoute> routes) {
        this.routes = routes;
    }

    public List<TransportShape> getShapes() {
        return shapes;
    }

    public void setShapes(List<TransportShape> shapes) {
        this.shapes = shapes;
    }
}
