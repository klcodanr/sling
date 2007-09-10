/*
 * Copyright 2007 The Apache Software Foundation.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at 
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.sling.maven.bundlesupport;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.jar.JarInputStream;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;
import java.util.zip.Deflater;

import org.apache.commons.httpclient.HttpClient;
import org.apache.commons.httpclient.HttpStatus;
import org.apache.commons.httpclient.methods.PostMethod;
import org.apache.commons.httpclient.methods.multipart.FilePart;
import org.apache.commons.httpclient.methods.multipart.FilePartSource;
import org.apache.commons.httpclient.methods.multipart.MultipartRequestEntity;
import org.apache.commons.httpclient.methods.multipart.Part;
import org.apache.commons.httpclient.methods.multipart.StringPart;
import org.apache.commons.io.IOUtils;
import org.apache.maven.artifact.versioning.ArtifactVersion;
import org.apache.maven.artifact.versioning.OverConstrainedVersionException;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.project.MavenProject;

/**
 * Deploy a JAR representing an OSGi Bundle.
 *
 * @goal deploy
 * @phase deploy
 * @description deploy an OSGi bundle jar to the Day OBR
 */
public class BundleDeployMojo extends AbstractMojo {

	/**
     * The directory for the generated JAR.
     *
     * @parameter expression="${project.build.directory}"
     * @required
     */
    private String buildDirectory;

    /**
     * The name of the generated JAR file.
     *
     * @parameter alias="jarName" expression="${project.build.finalName}.jar"
     * @required
     */
    private String jarName;

    /**
     * The URL of the OBR.
     *
     * @parameter expression="${obr}" default-value="http://obr.dev.day.com"
     * @required
     */
    private String obr;

    /**
     * The Maven project.
     *
     * @parameter expression="${project}"
     * @required
     * @readonly
     */
    private MavenProject project;

	/**
	 * Execute this Mojo
	 */
	public void execute() throws MojoExecutionException {
        // only upload if packaging as an osgi-bundle
        File jarFile = new File(this.buildDirectory, this.jarName);
        if (!this.isBundle(jarFile)) {
            this.getLog().info(jarFile + " is not an OSGi Bundle, not uploading");
            return;
        }

        // if this is a snapshot, replace "SNAPSHOT" with the date generated
        // by the maven deploy plugin
        if ( this.project.getVersion().indexOf("SNAPSHOT") > 0 ) {
            // create new version string by replacing all '-' with '.'
            String newVersion = this.project.getArtifact().getVersion();
            int firstPos = newVersion.indexOf('-') + 1;
            int pos = 0;
            while (pos != -1) {
                pos = newVersion.indexOf('-');
                if ( pos != -1 ) {
                    newVersion = newVersion.substring(0, pos ) + '.' + newVersion.substring(pos+1);
                }
            }
            // now remove all dots after the third one
            pos = newVersion.indexOf('.', firstPos);
            while ( pos != -1 ) {
                newVersion = newVersion.substring(0, pos) + newVersion.substring(pos+1);
                pos = newVersion.indexOf('.', pos+1);
            }
            jarFile = this.changeVersion(jarFile, newVersion);
        } else {
            // if this is a final release append "final"
            try {
                final ArtifactVersion v = this.project.getArtifact().getSelectedVersion();
                if ( v.getBuildNumber() == 0 && v.getQualifier() == null ) {
                    final String newVersion = this.project.getArtifact().getVersion() + ".FINAL";
                    jarFile = this.changeVersion(jarFile, newVersion);
                }
            } catch (OverConstrainedVersionException ocve) {
                // we ignore this and don't append "final"!
            }
        }
        this.post(this.obr, jarFile);
	}

	private void post(String targetURL, File file) {
        this.getLog().info("Uploading " + file + " to " + targetURL);

        PostMethod filePost = new PostMethod(targetURL);

        try {
            Part[] parts = { new FilePart(file.getName(), new FilePartSource(file.getName(), file)),
                new StringPart("_noredir_", "_noredir_") };
            filePost.setRequestEntity(new MultipartRequestEntity(parts,
                filePost.getParams()));
            HttpClient client = new HttpClient();
            client.getHttpConnectionManager().getParams().setConnectionTimeout(
                5000);
            int status = client.executeMethod(filePost);
            if (status == HttpStatus.SC_OK) {
                InputStream res = filePost.getResponseBodyAsStream();
                String response = "";
                if (res != null) {
                    response = IOUtils.toString(res,
                        filePost.getResponseCharSet());
                }
                this.getLog().info("Upload complete: " + response);
            } else {
                this.getLog().error(
                    "Upload failed, cause: " + HttpStatus.getStatusText(status));
            }
        } catch (Exception ex) {
            this.getLog().error(ex.getClass().getName() + " " + ex.getMessage());
            ex.printStackTrace();
        } finally {
            filePost.releaseConnection();
        }
    }

    private boolean isBundle(File jarFile) {
        if (!jarFile.exists()) {
            this.getLog().debug("isBundle: " + jarFile + " does not exist");
            return false;
        }

        JarFile jaf = null;
        try {
            jaf = new JarFile(jarFile);
            Manifest manif = jaf.getManifest();
            if (manif == null) {
                this.getLog().debug("isBundle: Missing manifest in " + jarFile);
                return false;
            }

            String symbName =
                manif.getMainAttributes().getValue("Bundle-SymbolicName");
            if (symbName == null) {
                this.getLog().debug("isBundle: No Bundle-SymbolicName in " + jarFile);
                return false;
            }

            this.getLog().info("isBundle: " + jarFile + " contains Bundle " + symbName);
            return true;
        } catch (IOException ioe) {
            // TODO
        } finally {
            if (jaf != null) {
                try {
                    jaf.close();
                } catch (IOException ignore) {
                    // don't care
                }
            }
        }

        // fall back to not being a bundle
        return false;
    }

    /**
     * Change the version in jar
     * @param newVersion
     * @param file
     * @return
     * @throws MojoExecutionException
     */
    protected File changeVersion(File file, String newVersion)
    throws MojoExecutionException {
        String fileName = file.getName();
        int pos = fileName.indexOf(this.project.getVersion());
        fileName = fileName.substring(0, pos) + newVersion + fileName.substring(pos + this.project.getVersion().length());

        JarInputStream jis = null;
        JarOutputStream jos;
        OutputStream out = null;
        try {
            // now create a temporary file and update the version
            final JarFile sourceJar = new JarFile(file);
            final Manifest manifest = sourceJar.getManifest();
            manifest.getMainAttributes().putValue("Bundle-Version", newVersion);

            jis = new JarInputStream(new FileInputStream(file));
            final File destJar = new File(file.getParentFile(), fileName);
            out = new FileOutputStream(destJar);
            jos = new JarOutputStream(out, manifest);

            jos.setMethod(JarOutputStream.DEFLATED);
            jos.setLevel(Deflater.BEST_COMPRESSION);

            JarEntry entryIn = jis.getNextJarEntry();
            while (entryIn != null) {
                JarEntry entryOut = new JarEntry(entryIn.getName());
                entryOut.setTime(entryIn.getTime());
                entryOut.setComment(entryIn.getComment());
                jos.putNextEntry(entryOut);
                if (!entryIn.isDirectory()) {
                    IOUtils.copy(jis, jos);
                }
                jos.closeEntry();
                jis.closeEntry();
                entryIn = jis.getNextJarEntry();
            }

            // close the JAR file now to force writing
            jos.close();
            return destJar;
        } catch (IOException ioe) {
            throw new MojoExecutionException("Unable to update version in jar file.", ioe);
        } finally {
            IOUtils.closeQuietly(jis);
            IOUtils.closeQuietly(out);
        }


    }
}