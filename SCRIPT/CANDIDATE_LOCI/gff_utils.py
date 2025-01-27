import polars as pl
from attrs import define
from pathlib import Path

@define(slots=True, eq=True)
class GeneInfo:
    gene_id: str
    chr_id: str
    coding_start: int
    coding_end: int
    strand: int
    longest_intron: int
    def coding_region_length(self) -> int:
        """Calculate and return the coding region length."""
        return self.coding_end - self.coding_start + 1
     
def parse_gff(file_path):
    """
    Parse a GFF file and return a Polars DataFrame.

    Parameters:
        file_path (str): Path to the GFF file.

    Returns:
        pl.DataFrame: A Polars DataFrame containing the parsed GFF data with added mRNA and gene columns.
    """
    column_names = [
        "seqid", "source", "type", "start", "end", "score", "strand", "phase", "attributes"
    ]

    try:
        df = pl.read_csv(
            file_path,
            separator='\t',
            has_header=False,
            comment_prefix="#",
            new_columns=column_names
        )

        # Extract IDs from attributes column
        df = df.with_columns([
            df["attributes"].str.extract(r"ID=([^;]+)", 1).alias("ID"),
            df["attributes"].str.extract(r"Parent=([^;]+)", 1).alias("ParentID")
        ])

        # Populate mRNA column
        df = df.with_columns([
            pl.when(df["type"] == "mRNA").then(df["ID"]).otherwise(df["ParentID"]).alias("mRNA")
        ])

        # Create mapping for mRNA to gene relationships
        mRNA_mapping = (
            df.filter(df["type"] == "mRNA")
            .select(["ID", "ParentID"])
            .rename({"ID": "mRNA", "ParentID": "gene"})
        )

        # Join to populate gene column based on mRNA
        df = df.join(mRNA_mapping, on="mRNA", how="left")

        # Assign gene IDs to gene features
        df = df.with_columns([
            pl.when(df["type"] == "gene").then(df["ID"]).otherwise(df["gene"]).alias("gene")
        ])

        return df
    except Exception as e:
        print (f"Error parsing GFF file: {e}")
        exit(1)


def get_coding_regions(df):
    """
    Compute the min and max CDS coordinates for each gene.

    Parameters:
        df (pl.DataFrame): A Polars DataFrame containing parsed GFF data.

    Returns:
        pl.DataFrame: A DataFrame with the min and max CDS coordinates for each gene.
    """
    cds_coordinates = (
        df.filter(df["type"] == "CDS")
        .group_by("gene")
        .agg([
            pl.col("start").min().alias("coding_start"),
            pl.col("end").max().alias("coding_end"),
            pl.col("strand").first(),
            pl.col("seqid").first().alias("chr_id")
        ])
    )

    return cds_coordinates


def get_longest_intron(df) -> pl.DataFrame:
    """
    Compute the length of the longest intron for each gene.

    Parameters:
        df (pl.DataFrame): A Polars DataFrame containing parsed GFF data.

    Returns:
        pl.DataFrame: A DataFrame with the longest intron length for each gene.
    """
    # Step 1: Filter CDS features, sort by mRNA and start, and calculate previous mRNA and stop
    cds_with_prev = (
        df.filter(df["type"] == "CDS")
        .sort(["mRNA", "start"])
        .with_columns([
            pl.col("mRNA").shift(1).alias("prev_mRNA"),
            pl.col("end").shift(1).alias("prev_end")
        ])
    )

    # Step 2: Calculate intron lengths
    intron_lengths = (
        cds_with_prev
        .with_columns([
            pl.when(pl.col("mRNA") != pl.col("prev_mRNA"))
            .then(0)
            .otherwise(pl.col("start") - pl.col("prev_end") - 1).map_elements(lambda x: max(0, x), return_dtype=pl.Int64)
            .alias("intron_length")
        ])
    )

    # Step 3: Ensure genes with single exons are included with a value of 0
    all_genes = (
        df.select("gene").unique()
    )

    intron_aggregated = (
        intron_lengths
        .filter(pl.col("intron_length") > 0)  # Keep only valid introns
        .join(df.select(["mRNA", "gene"]).unique(), on="mRNA", how="left")
        .group_by("gene")
        .agg([
            pl.col("intron_length").max().alias("longest_intron")
        ])
    )

    longest_introns_by_gene = (
        all_genes
        .join(intron_aggregated, on="gene", how="left")
        .with_columns([
            pl.col("longest_intron").fill_null(0)
        ])
    )

    return longest_introns_by_gene

def gff_to_geneInfo(gff_file: str, intron_quantile:float) -> tuple[dict,int]:
    """
    Parse a GFF file and return a dictionary of GeneInfo objects keyed by prot_id.

    Parameters:
        gff_file (str): Path to the GFF file.
        intron_lg_quantile (float): The quantile to use for the default intron length.
    Returns:
        tuple: A tuple containing the dictionary of GeneInfo objects and the default intron length.
        dict: A dictionary with gene_id as keys and GeneInfo objects as values.
    """
    df= parse_gff(gff_file) 
    coding_regions_df = get_coding_regions(df)
    longest_intron_df = get_longest_intron(df)

    # Merge info from the three DataFrames
    merged_df = coding_regions_df.join(longest_intron_df, on="gene", how="left").fill_null(0)

    # Construct the dictionary of ProtInfo objects
    prot_dict = {
        row["gene"]: GeneInfo(
            gene_id=str(row["gene"]),
            chr_id=str(row["chr_id"]),
            coding_start=row["coding_start"],
            coding_end=row["coding_end"],
            strand = 1 if row["strand"] == "+" else -1,
            longest_intron=row["longest_intron"]
        )
        for row in merged_df.to_dicts()
    }
    default_intron_length =  longest_intron_df.select(pl.col("longest_intron").quantile(intron_quantile)).to_numpy()[0, 0]
    return (prot_dict,default_intron_length)

# Only expose ProtInfo and parse_gff_to_protinfo for external use
__all__ = ["ProtInfo", "gff_to_geneInfo"]

def main():
    # Example usage
    test_data_path = Path(__file__).parent /"tests"/ "data" / "ENSG00000160679.gff"
    df = parse_gff(test_data_path)
    coding_regions = get_coding_regions(df)
    longest_introns = get_longest_intron(df)

    print(coding_regions)
    print(longest_introns)

    (prot_dict,def_intron_lg) = gff_to_geneInfo(test_data_path,0.7)
    print(prot_dict)
    print(def_intron_lg)
if __name__ == "__main__":
    main()