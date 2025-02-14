package GamaGTFSUtils;

import gama.core.metamodel.shape.GamaPoint;
import gama.core.metamodel.shape.IShape;
import gama.core.runtime.IScope;
import gama.gaml.operators.spatial.SpatialProjections;

public class SpatialUtils {

    /**
     * Converts latitude and longitude to GAMA CRS.
     *
     * @param scope - The GAMA simulation scope.
     * @param lat - Latitude in EPSG:4326.
     * @param lon - Longitude in EPSG:4326.
     * @return Transformed GamaPoint in the GAMA CRS.
     */
    public static GamaPoint toGamaCRS(IScope scope, double lat, double lon) {
        // Create a GamaPoint for the original location
        GamaPoint rawLocation = new GamaPoint(lon, lat, 0.0); // Longitude (X), Latitude (Y), Altitude (Z)  

        // Transform the point to the GAMA CRS using "to_GAMA_CRS"
        IShape transformedShape = SpatialProjections.to_GAMA_CRS(scope, rawLocation, "EPSG:4326");

        // Return the location as a GamaPoint
        return (GamaPoint) transformedShape.getLocation();
    }
}