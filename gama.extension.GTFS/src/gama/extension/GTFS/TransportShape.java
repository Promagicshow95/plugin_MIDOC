package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.GamaShapeFactory;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialProjections;

import java.util.ArrayList;
import java.util.List;

public class TransportShape {
    private final int shapeId;
    private final List<GamaPoint> points;

    public TransportShape(int shapeId) {
        this.shapeId = shapeId;
        this.points = new ArrayList<>();
    }

    public void addPoint(double lat, double lon, IScope scope) {
        GamaPoint point = new GamaPoint(lon, lat, 0.0); // Longitude (X), Latitude (Y)
        points.add(SpatialProjections.to_GAMA_CRS(scope, point, "EPSG:4326").getLocation());
    }
    

    public int getShapeId() {
        return shapeId;
    }

    public List<GamaPoint> getPoints() {
        return points;
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Points: " + points.size();
    }
}
