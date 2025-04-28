package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import GamaGTFSUtils.SpatialUtils;
import java.util.List;
import java.util.ArrayList;

public class TransportShape {
    private final int shapeId;
    private String routeId;
    private int tripId = -1;
    private final IList<GamaPoint> points;
    private final List<Double> distances; // 👉 nouvelle liste des shape_dist_traveled
    private int routeType = -1;

    public TransportShape(int shapeId, String routeId) {  
        this.shapeId = shapeId;
        this.routeId = routeId;
        this.points = GamaListFactory.create();
        this.distances = new ArrayList<>();
    }

    public void addPoint(double lat, double lon, double shapeDist, IScope scope) {
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
        distances.add(shapeDist); // 👈 ajoute la distance cumulée
    }

    public IList<GamaPoint> getPoints() {
        return points;
    }

    public List<Double> getDistances() {
        return distances;
    }

    public int getShapeId() {
        return shapeId;
    }

    public String getRouteId() {
        return routeId;
    }

    public void setRouteId(String routeId) {
        this.routeId = routeId;
    }

    public int getRouteType() {
        return routeType;
    }

    public void setRouteType(int routeType) {
        this.routeType = routeType;
    }

    public int getTripId() {
        return tripId;
    }

    public void setTripId(int tripId) {
        this.tripId = tripId;
    }
    
    public IShape generateShape(IScope scope) {
        if (points.isEmpty()) {
            System.err.println("[ERROR] No points found for shapeId=" + shapeId);
            return null;
        }

        IList<IShape> shapePoints = GamaListFactory.create();
        for (GamaPoint point : points) {
            shapePoints.add(point);
        }

        return SpatialCreation.line(scope, shapePoints); // Crée une polyligne dans GAMA
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Route ID: " + routeId + ", Points: " + points.size();
    }
}
