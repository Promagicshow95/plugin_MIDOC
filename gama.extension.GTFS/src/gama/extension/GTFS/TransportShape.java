package gama.extension.GTFS;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialCreation;
import gama.core.util.GamaListFactory;
import gama.core.util.IList;
import GamaGTFSUtils.SpatialUtils;

import java.util.ArrayList;
import java.util.List;

public class TransportShape {
    private final int shapeId;
    private final IList<GamaPoint> points;  // Utilisation de IList pour compatibilité avec GAMA
    private IShape shape;  // Stockage de la polyline

    public TransportShape(int shapeId) {
        this.shapeId = shapeId;
        this.points = GamaListFactory.create();
        this.shape = null;
    }

    /**
     * Ajoute un point (converti en CRS) à la liste des points du trajet.
     */
    public void addPoint(double lat, double lon, IScope scope) {
        GamaPoint point = SpatialUtils.toGamaCRS(scope, lat, lon);
        points.add(point);
    }

    /**
     * Génère la polyline à partir des points collectés.
     */
    public void generateShape(IScope scope) {
        if (points.isEmpty()) {
            System.err.println("[ERROR] No points found for shapeId=" + shapeId);
            return;
        }

        // Conversion de IList<GamaPoint> → IList<IShape>
        IList<IShape> shapePoints = GamaListFactory.create();
        for (GamaPoint point : points) {
            shapePoints.add(point);  // GamaPoint implémente déjà IShape
        }

        //  Création de la polyline avec les points convertis
        this.shape = SpatialCreation.line(scope, shapePoints);

        // Vérification et logs
        if (this.shape != null) {
            System.out.println("[DEBUG] Polyline successfully created for Shape ID " + shapeId);
            System.out.println("[DEBUG] Polyline GAML format: " + this.shape.serializeToGaml(false));
        } else {
            System.err.println("[ERROR] Polyline creation failed for Shape ID " + shapeId);
        }
    }

    public int getShapeId() {
        return shapeId;
    }

    public IList<GamaPoint> getPoints() {
        return points;
    }

    public IShape getShape() {
        return shape;
    }

    @Override
    public String toString() {
        return "Shape ID: " + shapeId + ", Points: " + points.size() + ", Shape: " + (shape != null ? "Generated" : "NULL");
    }
}
