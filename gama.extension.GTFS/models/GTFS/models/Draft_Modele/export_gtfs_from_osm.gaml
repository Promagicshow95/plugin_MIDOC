model FilterGTFS

global skills: [gtfs_filter] {
    string gtfs_path <- "../../includes/tisseo_gtfs_v2";
    string osm_path <- "../../includes/map.osm";
    string output_path <- "../../includes/filtered_gtfs";

    init {
        do filter_gtfs_with_osm;
    }
}

experiment demo type: gui {}
