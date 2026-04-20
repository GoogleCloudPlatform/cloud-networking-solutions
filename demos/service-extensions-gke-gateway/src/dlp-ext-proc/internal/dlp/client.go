// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package dlp

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	dlpapi "cloud.google.com/go/dlp/apiv2"
	dlppb "cloud.google.com/go/dlp/apiv2/dlppb"
)

const (
	defaultInfoTypes     = "PERSON_NAME,EMAIL_ADDRESS,PHONE_NUMBER,CREDIT_CARD_NUMBER,US_SOCIAL_SECURITY_NUMBER,STREET_ADDRESS,IP_ADDRESS"
	defaultMinLikelihood = "LIKELY"
	maxBodySize          = 524288 // DLP API limit: 512 KB
)

// Config holds configuration for the DLP client.
type Config struct {
	ProjectID     string
	InfoTypes     string
	MinLikelihood string
}

// Client wraps the Google Cloud DLP API client.
type Client struct {
	dlpClient     *dlpapi.Client
	projectID     string
	infoTypes     []*dlppb.InfoType
	minLikelihood dlppb.Likelihood
}

// New creates a new DLP client using Application Default Credentials.
func New(ctx context.Context, cfg Config) (*Client, error) {
	dlpClient, err := dlpapi.NewClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create DLP client: %w", err)
	}

	infoTypesStr := cfg.InfoTypes
	if infoTypesStr == "" {
		infoTypesStr = defaultInfoTypes
	}

	infoTypes := parseInfoTypes(infoTypesStr)

	likelihoodStr := cfg.MinLikelihood
	if likelihoodStr == "" {
		likelihoodStr = defaultMinLikelihood
	}
	minLikelihood := parseLikelihood(likelihoodStr)

	slog.Info("DLP client initialized", "project", cfg.ProjectID, "info_types", len(infoTypes), "min_likelihood", minLikelihood.String())

	return &Client{
		dlpClient:     dlpClient,
		projectID:     cfg.ProjectID,
		infoTypes:     infoTypes,
		minLikelihood: minLikelihood,
	}, nil
}

// DeidentifyContent sends content to the DLP API for PII redaction.
// On failure, returns the original content and an error.
func (c *Client) DeidentifyContent(ctx context.Context, content []byte) ([]byte, error) {
	if len(content) == 0 {
		return content, nil
	}

	if len(content) > maxBodySize {
		slog.Warn("Body size exceeds DLP API limit, skipping redaction", "body_size", len(content), "limit", maxBodySize)
		return content, fmt.Errorf("body size %d exceeds DLP API limit of %d bytes", len(content), maxBodySize)
	}

	req := &dlppb.DeidentifyContentRequest{
		Parent: fmt.Sprintf("projects/%s", c.projectID),
		InspectConfig: &dlppb.InspectConfig{
			InfoTypes:     c.infoTypes,
			MinLikelihood: c.minLikelihood,
		},
		DeidentifyConfig: &dlppb.DeidentifyConfig{
			Transformation: &dlppb.DeidentifyConfig_InfoTypeTransformations{
				InfoTypeTransformations: &dlppb.InfoTypeTransformations{
					Transformations: []*dlppb.InfoTypeTransformations_InfoTypeTransformation{
						{
							PrimitiveTransformation: &dlppb.PrimitiveTransformation{
								Transformation: &dlppb.PrimitiveTransformation_ReplaceWithInfoTypeConfig{
									ReplaceWithInfoTypeConfig: &dlppb.ReplaceWithInfoTypeConfig{},
								},
							},
						},
					},
				},
			},
		},
		Item: &dlppb.ContentItem{
			DataItem: &dlppb.ContentItem_Value{
				Value: string(content),
			},
		},
	}

	resp, err := c.dlpClient.DeidentifyContent(ctx, req)
	if err != nil {
		return content, fmt.Errorf("DLP DeidentifyContent failed: %w", err)
	}

	return []byte(resp.GetItem().GetValue()), nil
}

// Close closes the underlying DLP API client.
func (c *Client) Close() error {
	return c.dlpClient.Close()
}

func parseInfoTypes(s string) []*dlppb.InfoType {
	parts := strings.Split(s, ",")
	infoTypes := make([]*dlppb.InfoType, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			infoTypes = append(infoTypes, &dlppb.InfoType{Name: p})
		}
	}
	return infoTypes
}

func parseLikelihood(s string) dlppb.Likelihood {
	switch strings.ToUpper(strings.TrimSpace(s)) {
	case "VERY_UNLIKELY":
		return dlppb.Likelihood_VERY_UNLIKELY
	case "UNLIKELY":
		return dlppb.Likelihood_UNLIKELY
	case "POSSIBLE":
		return dlppb.Likelihood_POSSIBLE
	case "LIKELY":
		return dlppb.Likelihood_LIKELY
	case "VERY_LIKELY":
		return dlppb.Likelihood_VERY_LIKELY
	default:
		slog.Warn("Unknown likelihood, defaulting to LIKELY", "value", s)
		return dlppb.Likelihood_LIKELY
	}
}
