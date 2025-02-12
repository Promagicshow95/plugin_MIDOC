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
    private final IList<GamaPoint> points;  // Liste des points

    public TransportShape(int shapeId) {
        this.shapeId = shapeId;
        this.points = GamaListFactory.create();
    }

    /**
     * Ajoute un point converti en CRS à la liste.
     */
    public void addPoint(double lat, double lon, IScope scope) {
        points.add(SpatialUtils.toGamaCRS(scope, lat, lon));
    }

    /**
     * Génère la polyline sans la stocker.
     */
    public IShape generateShape(IScope scope) {
        if (points.isEmpty()) {
            System.err.println("[ERROR] No points found for shapeId=" + shapeId);
            return null;
        }

        // Conversion en IList<IShape>
        IList<IShape> shapePoints = GamaListFactory.create();
        for (GamaPoint point : points) {
            shapePoints.add(point);  // GamaPoint implémente IShape
        }

        IShape polyline = SpatialCreation.line(scope, shapePoints);

        if (polyline != null) {
            System.out.println("[DEBUG] Polyline created for Shape ID " + shapeId);
        } else {
            System.err.println("[ERROR] Polyline creation failed for Shape ID " + shapeId);
        }

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
        return "Shape ID: " + shapeId + ", Points: " + points.size();
    }
}
