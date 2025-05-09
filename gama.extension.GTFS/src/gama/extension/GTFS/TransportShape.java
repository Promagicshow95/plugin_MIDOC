package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import GamaGTFSUtils.SpatialUtils;

public class TransportShape {
    private final int shapeId;
    private String routeId;
    private int tripId = -1;
    private final IList<GamaPoint> points; 
    private int routeType = -1;

    public TransportShape(int shapeId, String routeId) {  
        this.shapeId = shapeId;
        this.routeId = routeId;
        this.points = GamaListFactory.create();
    }

    public void addPoint(double lat, double lon, IScope scope) {
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
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

        return SpatialCreation.line(scope, shapePoints);
    }

    public int getShapeId() {
        return shapeId;
    }

    public IList<GamaPoint> getPoints() {
        return points;
    }

    public String getRouteId() {
        return routeId;
    }

    public void setRouteId(String routeId) {
        System.out.println("[DEBUG] Setting routeId for ShapeId=" + shapeId + " -> " + routeId);
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
        System.out.println("[DEBUG] Setting tripId for ShapeId=" + shapeId + " -> " + tripId);
        this.tripId = tripId;
    }
    
    public IShape getGeometry(IScope scope) {
        return generateShape(scope);
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Route ID: " + routeId + ", Route Type: " + routeType + ", Points: " + points.size();
    }
}
