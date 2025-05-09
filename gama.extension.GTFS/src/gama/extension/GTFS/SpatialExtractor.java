package gama.extension.GTFS;

import java.util.*;
import org.locationtech.jts.geom.Geometry;
import gama.core.runtime.IScope;

public class SpatialExtractor {

    private final GTFS_reader gtfsReader;
    private final IScope scope;

    public SpatialExtractor(GTFS_reader reader, IScope scope) {
        this.gtfsReader = reader;
        this.scope = scope;
    }

    public Set<String> selectStopIdsInRegion(Geometry region) {
        Set<String> stopIds = new HashSet<>();
        for (TransportStop stop : gtfsReader.getStops()) {
            Geometry stopGeom = stop.getGeometry().getInnerGeometry(); // Convert GamaPoint → JTS Geometry
            if (region.contains(stopGeom)) {
                stopIds.add(stop.getStopId());
            }
        }
        return stopIds;
    }

    public Set<Integer> selectShapeIdsInRegion(Geometry region) {
        Set<Integer> shapeIds = new HashSet<>();
        for (TransportShape shape : gtfsReader.getShapes()) {
            Geometry shapeGeom = shape.getGeometry(scope).getInnerGeometry(); // IShape → Geometry
            if (region.intersects(shapeGeom)) {
                shapeIds.add(shape.getShapeId());
            }
        }
        return shapeIds;
    }

    public Set<String> selectTripsInRegion(Set<String> stopIdsInRegion, Set<Integer> shapeIdsInRegion) {
        Set<String> trips = new HashSet<>();
        for (TransportTrip trip : gtfsReader.getTrips()) {
            if (shapeIdsInRegion.contains(trip.getShapeId())) {
                trips.add(String.valueOf(trip.getTripId()));
                continue;
            }
            for (String stopId : trip.getStopsInOrder()) {
                if (stopIdsInRegion.contains(stopId)) {
                    trips.add(String.valueOf(trip.getTripId()));
                    break;
                }
            }
        }
        return trips;
    }

    public List<TransportStop> filterStops(Set<String> stopIds) {
        List<TransportStop> result = new ArrayList<>();
        for (TransportStop stop : gtfsReader.getStops()) {
            if (stopIds.contains(stop.getStopId())) {
                result.add(stop);
            }
        }
        return result;
    }

    public List<TransportTrip> filterTrips(Set<String> tripIds) {
        List<TransportTrip> result = new ArrayList<>();
        for (TransportTrip trip : gtfsReader.getTrips()) {
            if (tripIds.contains(String.valueOf(trip.getTripId()))) {
                result.add(trip);
            }
        }
        return result;
    }

    public List<TransportRoute> filterRoutes(Set<String> tripIds) {
        Set<String> routeIds = new HashSet<>();
        for (TransportTrip trip : gtfsReader.getTrips()) {
            if (tripIds.contains(String.valueOf(trip.getTripId()))) {
                routeIds.add(trip.getRouteId());
            }
        }
        List<TransportRoute> result = new ArrayList<>();
        for (TransportRoute route : gtfsReader.getRoutes()) {
            if (routeIds.contains(route.getRouteId())) {
                result.add(route);
            }
        }
        return result;
    }

    public List<TransportShape> filterShapes(Set<Integer> shapeIds) {
        List<TransportShape> result = new ArrayList<>();
        for (TransportShape shape : gtfsReader.getShapes()) {
            if (shapeIds.contains(shape.getShapeId())) {
                result.add(shape);
            }
        }
        return result;
    }

    public FilteredGtfsData filterGTFSByRegion(Geometry region) {
        Set<String> stopIdsInRegion = selectStopIdsInRegion(region);
        Set<Integer> shapeIdsInRegion = selectShapeIdsInRegion(region);
        Set<String> tripsInRegion = selectTripsInRegion(stopIdsInRegion, shapeIdsInRegion);

        FilteredGtfsData result = new FilteredGtfsData();
        result.setStops(filterStops(stopIdsInRegion));
        result.setTrips(filterTrips(tripsInRegion));
        result.setRoutes(filterRoutes(tripsInRegion));
        result.setShapes(filterShapes(shapeIdsInRegion));
        return result;
    }
}
