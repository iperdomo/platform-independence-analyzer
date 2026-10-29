use aws_sdk_s3::Client;

pub async fn client() -> Client {
    Client::new(&aws_config::load_from_env().await)
}
