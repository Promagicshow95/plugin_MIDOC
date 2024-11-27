package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.gaml.operators.spatial.SpatialProjections;
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
        // Use the utility method for CRS conversion
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
    }


    public int getShapeId() {
        return shapeId;
    }

    public List<GamaPoint> getPoints() {
        return points;
    }
    

    /**
     * Converts the list of GamaPoints into a polyline (IShape).
     *
     * @param scope The GAMA simulation scope.
     * @return IShape representing the polyline.
     */
    public IShape toPolyline(IScope scope) {
        if (points.isEmpty()) {
            throw new IllegalStateException("No points available to convert to polyline.");
        }

        // Convert List<GamaPoint> to IList<IShape>
        IList<IShape> shapes = GamaListFactory.create();
        for (GamaPoint point : points) {
            shapes.add(point); // Ajout direct si GamaPoint implémente IShape
        }

        // Créez une polyline à partir des shapes
        return SpatialCreation.line(scope, shapes);
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Points: " + points.size();
    }
}
