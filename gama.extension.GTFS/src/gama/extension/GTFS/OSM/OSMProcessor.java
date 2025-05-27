package gama.extension.GTFS.OSM;

import org.geotools.data.*;
import org.geotools.data.shapefile.ShapefileDataStore;
import org.geotools.data.shapefile.ShapefileDataStoreFactory;
import org.geotools.data.simple.*;
import org.geotools.feature.simple.SimpleFeatureTypeBuilder;
import org.geotools.feature.DefaultFeatureCollection;
import org.opengis.feature.simple.SimpleFeatureType;
import org.locationtech.jts.geom.Point; 

import java.io.File;
import java.io.Serializable;
import java.util.*;

public class OSMProcessor {

    public static void exportOsmToShapefile(String osmPath, String outputDir) throws Exception {
       

        // Création du shapefile pour les noeuds (points)
        File newShapefile = new File(outputDir, "osm_nodes.shp");

        SimpleFeatureTypeBuilder b = new SimpleFeatureTypeBuilder();
        b.setName("Node");
        b.add("the_geom", Point.class); // org.locationtech.jts.geom.Point
        b.add("id", String.class);
        final SimpleFeatureType TYPE = b.buildFeatureType();

        DefaultFeatureCollection collection = new DefaultFeatureCollection();

        // TODO: Ajouter les features à la collection ici (ex : à partir de ton parsing OSM)
        // Exemple :
        // Point pt = ...; // Géométrie JTS créée à partir du parsing OSM
        // SimpleFeature feature = SimpleFeatureBuilder.build(TYPE, new Object[]{pt, "node_id"}, null);
        // collection.add(feature);

        ShapefileDataStoreFactory dataStoreFactory = new ShapefileDataStoreFactory();
        Map<String, Serializable> params = new HashMap<>();
        params.put("url", newShapefile.toURI().toURL());
        params.put("create spatial index", Boolean.TRUE);

        ShapefileDataStore newDataStore = (ShapefileDataStore) dataStoreFactory.createNewDataStore(params);
        newDataStore.createSchema(TYPE);

        
        String typeName = newDataStore.getTypeNames()[0];
        SimpleFeatureSource featureSource = newDataStore.getFeatureSource(typeName);

        if (featureSource instanceof SimpleFeatureStore) {
            SimpleFeatureStore featureStore = (SimpleFeatureStore) featureSource;
            featureStore.setTransaction(Transaction.AUTO_COMMIT);
            featureStore.addFeatures(collection);
         
        } else {
            throw new IllegalStateException(typeName + " does not support read/write access");
        }
    }
}
