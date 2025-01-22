package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;

import java.util.ArrayList;
import java.util.List;

import GamaGTFSUtils.SpatialUtils;

public class TransportShape {
    private final int shapeId;
    private final List<GamaPoint> points;

    public TransportShape(int shapeId) {
        this.shapeId = shapeId;
        this.points = new ArrayList<>();
    }

    public void addPoint(double lat, double lon, IScope scope) {
        // Utilisation d'une méthode utilitaire pour la conversion CRS
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
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
