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
    private final IList<GamaPoint> points; 
    private int routeType = -1;

    public TransportShape(int shapeId) {
        this.shapeId = shapeId;
        this.points = GamaListFactory.create();
    }

    /**
     * Adds a point converted into CRS to the list.
     */
    public void addPoint(double lat, double lon, IScope scope) {
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
    }

    /**
     * Generates the polyline without storing it
     */
    public IShape generateShape(IScope scope) {
        if (points.isEmpty()) {
            System.err.println("[ERROR] No points found for shapeId=" + shapeId);
            return null;
        }

        IList<IShape> shapePoints = GamaListFactory.create();
        for (GamaPoint point : points) {
            shapePoints.add(point);
        }

        IShape polyline = SpatialCreation.line(scope, shapePoints);
        return polyline;
    }

    public int getShapeId() {
        return shapeId;
    }

    public IList<GamaPoint> getPoints() {
        return points;
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Route Type: " + routeType + ", Points: " + points.size();
    }

    public void setRouteType(int routeType) {
        this.routeType = routeType;
        System.out.println("[DEBUG] Shape ID " + shapeId + " assigned routeType: " + routeType);
    }
    
	public int getRouteType() {
        return routeType;
    }
}
