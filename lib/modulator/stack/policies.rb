module StackBuilder
  module LambdaPolicy
    module_function

    # add inline iam role to lambda, NOTE: use the same role for all lambdas for now
    def add_lambda_iam_role(function_name: nil)
      StackBuilder.stack.add('LambdaRole', Humidifier::IAM::Role.new(
          assume_role_policy_document: {
            "Version" => "2012-10-17",
            'Statement' => [
              {
                "Action" => ["sts:AssumeRole"],
                "Effect" => "Allow",
                'Principal' => {
                  'Service' => ["lambda.amazonaws.com"]
                }
              }
            ]
          },
          policies: []
        )
      )
    end

    def add_policy(policy, **opts)
      StackBuilder.stack.resources['LambdaRole'].properties['policies'] << send(policy, opts)
    end

    # policy to access cloudwatch
    def cloudwatch(**opts)
      {
        "policy_document" => {
          "Version" => "2012-10-17",
          'Statement' => [
            {
              "Sid" => "AllowLogCreation",
              "Action" => [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
              ],
              "Effect" => "Allow",
              "Resource" => Humidifier.fn.sub("arn:aws:logs:${AWS::Region}:${AWS::AccountId}:*")
            },
            {
              "Sid" => "AllowLogGroupCreation",
              "Action" => [
                "logs:CreateLogGroup",
              ],
              "Effect" => "Allow",
              "Resource" => "*"
            }
          ]
        },
        "policy_name" => "cloud-watch-access"
      }
    end

    # policy to access prefixed dynamo tables
    def dynamo_db(**opts)
      prefixes = opts[:prefixes] || []
      prefix_separator = opts[:prefix_separator] || '-'
      wildcard = '*'
      if prefixes.any?
        prefixes.map!{|prefix| prefix == :app_name ? StackBuilder.stack.app_name.dasherize.split('-') : prefix}
        wildcard = "#{(prefixes << '*').join(prefix_separator)}"
      end
      {
        "policy_document" => {
          "Version" => "2012-10-17",
          'Statement' => [
            {
              "Sid" => "AllowAllActionsOnPrefixedTable",
              "Effect" => "Allow",
              "Action" => [
                  "dynamodb:*"
              ],
              "Resource" => Humidifier.fn.sub("arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/#{wildcard}")
            },
            {
              "Sid" => "AdditionalPrivileges",
              "Effect" => "Allow",
              "Action" => [
                  "dynamodb:ListTables",
                  "dynamodb:DescribeTable"
              ],
              "Resource" => "*"
            }
          ]
        },
        "policy_name" => "dynamo-db-access"
      }
    end

    # TODO: add access to named secrets
    def secret_manager(**opts)

    end
  end
end
