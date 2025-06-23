package GamaGTFSUtils; 

import java.io.File;
import java.io.FileNotFoundException;

import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.locationtech.jts.geom.Envelope;

public class OSMUtils {

    public static Envelope extractEnvelope(String osmPath) throws Exception {
        File osmFile = new File(osmPath);

        if (!osmFile.exists() || !osmFile.isFile()) {
            throw new FileNotFoundException("OSM file not found at path: " + osmPath);
        }

        Document doc = DocumentBuilderFactory.newInstance()
                            .newDocumentBuilder().parse(osmFile);
        
        Element bounds = (Element) doc.getElementsByTagName("bounds").item(0);
        
        if (bounds == null) {
            throw new IllegalArgumentException("No <bounds> element found in OSM file: " + osmPath);
        }
        
        double minLat = Double.parseDouble(bounds.getAttribute("minlat"));
        double minLon = Double.parseDouble(bounds.getAttribute("minlon"));
        double maxLat = Double.parseDouble(bounds.getAttribute("maxlat"));
        double maxLon = Double.parseDouble(bounds.getAttribute("maxlon"));
        
        return new Envelope(minLon, maxLon, minLat, maxLat);
    }
}