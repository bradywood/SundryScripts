#!/bin/bash

# --- Configuration ---
# Get the current AWS region from the AWS config file.
# You can also hardcode a region here, e.g., AWS_REGION="us-east-1"
AWS_REGION=$(aws configure get region)
echo "Checking Aurora DB Clusters in region: $AWS_REGION"
echo "=================================================="

# --- Main Logic ---

# STEP 1: Fetch all cluster and instance data in a single pass to be efficient.
# This avoids making an API call for every instance inside the loop (N+1 problem).
ALL_CLUSTERS_JSON=$(aws rds describe-db-clusters --region "$AWS_REGION" --output json)
ALL_INSTANCES_JSON=$(aws rds describe-db-instances --region "$AWS_REGION" --output json)

# Check if the API calls were successful
if [ -z "$ALL_CLUSTERS_JSON" ]; then
    echo "Error: Failed to fetch DB cluster information. Check your AWS CLI configuration and permissions."
    exit 1
fi

# STEP 2: Iterate through each cluster found.
echo "$ALL_CLUSTERS_JSON" | jq -c '.DBClusters[]' | while read -r cluster_json; do

    # Extract the cluster identifier and engine
    CLUSTER_IDENTIFIER=$(echo "$cluster_json" | jq -r '.DBClusterIdentifier')
    ENGINE=$(echo "$cluster_json" | jq -r '.Engine')

    # Filter for Aurora clusters
    if [[ "$ENGINE" != "aurora"* ]]; then
        continue
    fi

    # Get the list of member instance identifiers for the current cluster
    MEMBER_IDS=$(echo "$cluster_json" | jq -r '[.DBClusterMembers[].DBInstanceIdentifier] | @json')

    # STEP 3: Correlate with instance data to find the true AZ for each member.
    # We filter the ALL_INSTANCES_JSON data blob for instances whose identifiers
    # are in the MEMBER_IDS list for this specific cluster.
    MEMBERS_DATA=$(echo "$ALL_INSTANCES_JSON" | jq -c --argjson ids "$MEMBER_IDS" '[.DBInstances[] | select(.DBInstanceIdentifier as $id | $ids | index($id))]')

    # From this filtered data, build the report strings
    MEMBERS_INFO=$(echo "$MEMBERS_DATA" | jq -r 'map("\(.DBInstanceIdentifier)(\(if .DBClusterIdentifier == .DBInstanceIdentifier then "WRITER" else "READER" end)) in \(.AvailabilityZone)") | join(", ")')
    UNIQUE_AZS=$(echo "$MEMBERS_DATA" | jq -r '[.[].AvailabilityZone] | unique | sort | join(", ")')
    AZ_COUNT=$(echo "$MEMBERS_DATA" | jq -r '[.[].AvailabilityZone] | unique | length')


    # --- Print the Report for the Cluster ---
    echo "Cluster: '$CLUSTER_IDENTIFIER' ($ENGINE)"

    # Check the count of unique AZs to determine Multi-AZ status for compute.
    if [ "$AZ_COUNT" -gt 1 ]; then
        echo "  -> STATUS: Multi-AZ Compute is ENABLED."
    elif [ "$AZ_COUNT" -eq 1 ]; then
        echo "  -> STATUS: Multi-AZ Compute is DISABLED (Single AZ)."
    else
        echo "  -> STATUS: UNKNOWN (No running instances found for this cluster)."
    fi

    # Print the details of members and their AZs.
    if [ "$AZ_COUNT" -gt 0 ]; then
      echo "  -> Member Instances: $AZ_COUNT unique AZ(s): [$UNIQUE_AZS]"
      echo "  -> Detailed Members: [$MEMBERS_INFO]"
    fi
    echo "--------------------------------------------------"

done
