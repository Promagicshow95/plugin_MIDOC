model FilterGTFS

global skills: [gtfs_filter] {
    string gtfs_path <- "../../includes/nantes_gtfs";
    string osm_path <- "../../includes/Nantes_map (2).osm";
    string output_path <- "../../includes/filtered_gtfs";

    init {
        do filter_gtfs_with_osm;
    }
}

experiment demo type: gui {}
